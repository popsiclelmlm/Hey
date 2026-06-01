#include "napi/native_api.h"

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <dlfcn.h>
#include <hilog/log.h>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr unsigned int LOG_DOMAIN_ID = 0x0001;
constexpr const char* LOG_TAG_NAME = "HeyNative";

using XrayRunFromJsonFn = char* (*)(const char*);
using XrayStopFn = char* (*)();
using TunStartFn = int (*)(int, const char*, int, int);
using TunStopFn = void (*)();
using TunStatsFn = int64_t (*)();

struct XraySymbols {
    void* handle = nullptr;
    XrayRunFromJsonFn runFromJson = nullptr;
    XrayStopFn stop = nullptr;
};

struct TunSymbols {
    void* handle = nullptr;
    TunStartFn start = nullptr;
    TunStopFn stop = nullptr;
    TunStatsFn uploadBytes = nullptr;
    TunStatsFn downloadBytes = nullptr;
};

std::atomic_bool g_xrayRunning(false);
std::atomic_bool g_tunRunning(false);
std::atomic<int64_t> g_uploadBytes(0);
std::atomic<int64_t> g_downloadBytes(0);
std::string g_lastMessage = "Native bridge ready. Waiting for libxray.so and libheytun2socks.so.";
XraySymbols g_xray;
TunSymbols g_tun;

const char* BASE64_TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void LogInfo(const std::string& message)
{
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN_ID, LOG_TAG_NAME, "%{public}s", message.c_str());
}

void LogWarn(const std::string& message)
{
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN_ID, LOG_TAG_NAME, "%{public}s", message.c_str());
}

void LogError(const std::string& message)
{
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN_ID, LOG_TAG_NAME, "%{public}s", message.c_str());
}

std::string LastDlError()
{
    const char* error = dlerror();
    return error == nullptr ? "unknown dlerror" : std::string(error);
}

std::string GetStringArg(napi_env env, napi_value value)
{
    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::string result(length + 1, '\0');
    napi_get_value_string_utf8(env, value, &result[0], result.size(), &length);
    result.resize(length);
    return result;
}

int32_t GetIntArg(napi_env env, napi_value value)
{
    int32_t result = 0;
    napi_get_value_int32(env, value, &result);
    return result;
}

napi_value CreateString(napi_env env, const std::string& value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
    return result;
}

napi_value CreateBool(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value CreateInt64(napi_env env, int64_t value)
{
    napi_value result = nullptr;
    napi_create_int64(env, value, &result);
    return result;
}

napi_value CreateResult(napi_env env, bool ok, const std::string& message)
{
    napi_value result = nullptr;
    napi_create_object(env, &result);
    napi_set_named_property(env, result, "ok", CreateBool(env, ok));
    napi_set_named_property(env, result, "message", CreateString(env, message));
    g_lastMessage = message;
    if (ok) {
        LogInfo(message);
    } else {
        LogError(message);
    }
    return result;
}

std::string Base64Encode(const std::string& input)
{
    std::string output;
    int value = 0;
    int bits = -6;
    for (uint8_t ch : input) {
        value = (value << 8) + ch;
        bits += 8;
        while (bits >= 0) {
            output.push_back(BASE64_TABLE[(value >> bits) & 0x3F]);
            bits -= 6;
        }
    }
    if (bits > -6) {
        output.push_back(BASE64_TABLE[((value << 8) >> (bits + 8)) & 0x3F]);
    }
    while (output.size() % 4 != 0) {
        output.push_back('=');
    }
    return output;
}

std::string Base64Decode(const std::string& input)
{
    std::string output;
    std::vector<int> values(256, -1);
    for (int index = 0; index < 64; index++) {
        values[static_cast<uint8_t>(BASE64_TABLE[index])] = index;
    }

    int value = 0;
    int bits = -8;
    for (char ch : input) {
        if (ch == '=') {
            break;
        }
        int decoded = values[static_cast<uint8_t>(ch)];
        if (decoded < 0) {
            continue;
        }
        value = (value << 6) + decoded;
        bits += 6;
        if (bits >= 0) {
            output.push_back(static_cast<char>((value >> bits) & 0xFF));
            bits -= 8;
        }
    }
    return output;
}

std::string JsonEscape(const std::string& input)
{
    std::ostringstream output;
    for (char ch : input) {
        switch (ch) {
            case '\\':
                output << "\\\\";
                break;
            case '"':
                output << "\\\"";
                break;
            case '\n':
                output << "\\n";
                break;
            case '\r':
                output << "\\r";
                break;
            case '\t':
                output << "\\t";
                break;
            default:
                output << ch;
                break;
        }
    }
    return output.str();
}

bool ResponseOk(const std::string& base64Response, std::string& message)
{
    std::string decoded = Base64Decode(base64Response);
    if (decoded.empty()) {
        message = "Empty libXray response.";
        return false;
    }
    if (decoded.find("\"success\":true") != std::string::npos) {
        message = "libXray response: " + decoded;
        return true;
    }

    size_t errorKey = decoded.find("\"error\":\"");
    if (errorKey != std::string::npos) {
        size_t start = errorKey + 9;
        size_t end = decoded.find('"', start);
        message = decoded.substr(start, end == std::string::npos ? std::string::npos : end - start);
    } else {
        message = decoded;
    }
    return false;
}

bool LoadXray()
{
    if (g_xray.handle != nullptr) {
        return g_xray.runFromJson != nullptr && g_xray.stop != nullptr;
    }

    LogInfo("Loading libxray.so.");
    g_xray.handle = dlopen("libxray.so", RTLD_NOW | RTLD_LOCAL);
    if (g_xray.handle == nullptr) {
        g_lastMessage = "dlopen libxray.so failed: " + LastDlError();
        LogError(g_lastMessage);
        return false;
    }
    g_xray.runFromJson = reinterpret_cast<XrayRunFromJsonFn>(dlsym(g_xray.handle, "CGoRunXrayFromJSON"));
    g_xray.stop = reinterpret_cast<XrayStopFn>(dlsym(g_xray.handle, "CGoStopXray"));
    if (g_xray.runFromJson == nullptr || g_xray.stop == nullptr) {
        g_lastMessage = "dlsym libxray.so failed: " + LastDlError();
        LogError(g_lastMessage);
        return false;
    }
    LogInfo("libxray.so loaded.");
    return true;
}

bool LoadTun2Socks()
{
    if (g_tun.handle != nullptr) {
        return g_tun.start != nullptr && g_tun.stop != nullptr;
    }

    LogInfo("Loading libheytun2socks.so.");
    g_tun.handle = dlopen("libheytun2socks.so", RTLD_NOW | RTLD_LOCAL);
    if (g_tun.handle == nullptr) {
        g_lastMessage = "dlopen libheytun2socks.so failed: " + LastDlError();
        LogError(g_lastMessage);
        return false;
    }
    g_tun.start = reinterpret_cast<TunStartFn>(dlsym(g_tun.handle, "HeyTun2SocksStart"));
    g_tun.stop = reinterpret_cast<TunStopFn>(dlsym(g_tun.handle, "HeyTun2SocksStop"));
    g_tun.uploadBytes = reinterpret_cast<TunStatsFn>(dlsym(g_tun.handle, "HeyTun2SocksUploadBytes"));
    g_tun.downloadBytes = reinterpret_cast<TunStatsFn>(dlsym(g_tun.handle, "HeyTun2SocksDownloadBytes"));
    if (g_tun.start == nullptr || g_tun.stop == nullptr) {
        g_lastMessage = "dlsym libheytun2socks.so failed: " + LastDlError();
        LogError(g_lastMessage);
        return false;
    }
    if (g_tun.uploadBytes == nullptr || g_tun.downloadBytes == nullptr) {
        LogWarn("tun2socks adapter stats symbols missing; forwarding can still start.");
    }
    LogInfo("libheytun2socks.so loaded.");
    return true;
}

std::string CallXrayRunFromJson(const std::string& config)
{
    std::string request = "{\"datDir\":\"\",\"configJSON\":\"" + JsonEscape(config) + "\"}";
    char* raw = g_xray.runFromJson(Base64Encode(request).c_str());
    std::string response = raw == nullptr ? "" : raw;
    if (raw != nullptr) {
        free(raw);
    }
    return response;
}

napi_value ValidateConfig(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResult(env, false, "Missing Xray config JSON.");
    }

    std::string config = GetStringArg(env, args[0]);
    if (config.empty()) {
        return CreateResult(env, false, "Xray config JSON is empty.");
    }
    if (config.find("\"inbounds\"") == std::string::npos || config.find("\"outbounds\"") == std::string::npos) {
        return CreateResult(env, false, "Generated Xray config must contain inbounds and outbounds.");
    }
    if (LoadXray()) {
        return CreateResult(env, true, "Native config preflight passed. libXray is available.");
    }
    return CreateResult(env, false, g_lastMessage);
}

napi_value StartXray(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResult(env, false, "Missing Xray config JSON.");
    }

    std::string config = GetStringArg(env, args[0]);
    if (config.empty()) {
        return CreateResult(env, false, "Xray config JSON is empty.");
    }
    if (g_xrayRunning.load()) {
        return CreateResult(env, true, "Xray already running.");
    }

    if (!LoadXray()) {
        g_xrayRunning.store(false);
        return CreateResult(env, false, g_lastMessage);
    }

    std::string message;
    bool ok = ResponseOk(CallXrayRunFromJson(config), message);
    if (!ok) {
        g_xrayRunning.store(false);
        return CreateResult(env, false, "libXray start failed: " + message);
    }
    g_xrayRunning.store(true);
    return CreateResult(env, true, "libXray started.");
}

napi_value StopXray(napi_env env, napi_callback_info info)
{
    (void)info;
    if (!g_xrayRunning.load()) {
        return CreateResult(env, true, "Xray already stopped.");
    }

    if (LoadXray()) {
        char* raw = g_xray.stop();
        std::string response = raw == nullptr ? "" : raw;
        if (raw != nullptr) {
            free(raw);
        }
        std::string message;
        bool ok = ResponseOk(response, message);
        if (!ok) {
            g_xrayRunning.store(false);
            return CreateResult(env, false, "libXray stop failed: " + message);
        }
    }
    g_xrayRunning.store(false);
    return CreateResult(env, true, "Xray stopped.");
}

napi_value StartTun2Socks(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 4) {
        return CreateResult(env, false, "Missing tun2socks arguments.");
    }

    int32_t tunFd = GetIntArg(env, args[0]);
    std::string host = GetStringArg(env, args[1]);
    int32_t port = GetIntArg(env, args[2]);
    int32_t mtu = GetIntArg(env, args[3]);

    if (tunFd < 0) {
        return CreateResult(env, false, "Invalid TUN fd.");
    }
    if (host.empty() || port <= 0 || port > 65535 || mtu < 576 || mtu > 1500) {
        return CreateResult(env, false, "Invalid tun2socks host, port, or MTU.");
    }
    if (g_tunRunning.load()) {
        return CreateResult(env, true, "tun2socks already running.");
    }

    g_uploadBytes.store(0);
    g_downloadBytes.store(0);
    if (!LoadTun2Socks()) {
        g_tunRunning.store(false);
        return CreateResult(env, false, g_lastMessage);
    }

    int result = g_tun.start(tunFd, host.c_str(), port, mtu);
    if (result != 0) {
        g_tunRunning.store(false);
        return CreateResult(env, false, "tun2socks adapter start failed.");
    }
    g_tunRunning.store(true);
    return CreateResult(env, true, "tun2socks adapter started.");
}

napi_value StopTun2Socks(napi_env env, napi_callback_info info)
{
    (void)info;
    if (!g_tunRunning.load()) {
        return CreateResult(env, true, "tun2socks already stopped.");
    }
    if (LoadTun2Socks()) {
        g_tun.stop();
    }
    g_tunRunning.store(false);
    return CreateResult(env, true, "tun2socks stopped.");
}

napi_value GetStats(napi_env env, napi_callback_info info)
{
    (void)info;
    if (LoadTun2Socks()) {
        if (g_tun.uploadBytes != nullptr) {
            g_uploadBytes.store(g_tun.uploadBytes());
        }
        if (g_tun.downloadBytes != nullptr) {
            g_downloadBytes.store(g_tun.downloadBytes());
        }
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    napi_set_named_property(env, result, "uploadBytes", CreateInt64(env, g_uploadBytes.load()));
    napi_set_named_property(env, result, "downloadBytes", CreateInt64(env, g_downloadBytes.load()));
    napi_set_named_property(env, result, "xrayRunning", CreateBool(env, g_xrayRunning.load()));
    napi_set_named_property(env, result, "tun2SocksRunning", CreateBool(env, g_tunRunning.load()));
    napi_set_named_property(env, result, "lastMessage", CreateString(env, g_lastMessage));
    return result;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "validateConfig", nullptr, ValidateConfig, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startXray", nullptr, StartXray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopXray", nullptr, StopXray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startTun2Socks", nullptr, StartTun2Socks, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopTun2Socks", nullptr, StopTun2Socks, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getStats", nullptr, GetStats, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module heyVpnModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "heyvpn",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterHeyVpnModule(void)
{
    napi_module_register(&heyVpnModule);
}
