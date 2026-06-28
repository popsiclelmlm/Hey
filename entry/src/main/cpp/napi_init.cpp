#include "napi/native_api.h"

#include <atomic>
#include <thread>
#include <cctype>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <hilog/log.h>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>

namespace {

constexpr unsigned int LOG_DOMAIN_ID = 0x0001;
constexpr const char* LOG_TAG_NAME = "HeyNative";
constexpr const char* XRAY_CONFIG_FILE = "hey-xray-config.json";
constexpr const char* XRAY_CORE_LIB = "libxray.so";
constexpr const char* PING_CONFIG_FILE = "hey-ping-config.json";
constexpr const char* TEST_CONFIG_FILE = "hey-xray-test-config.json";

using CGoPingFunc = char* (*)(char*);
using CGoStringFunc = char* (*)(char*);
using CGoStopFunc = char* (*)();
using CGoVersionFunc = char* (*)();
using CGoFreePortsFunc = char* (*)(int64_t);
using CGoSetTunFdFunc = void (*)(int);

std::atomic_bool g_xrayRunning(false);
std::atomic_bool g_tunRunning(false);
std::atomic<int64_t> g_uploadBytes(0);
std::atomic<int64_t> g_downloadBytes(0);
std::string g_lastMessage = "Native bridge ready. Waiting for Xray shared library.";
void* g_xrayHandle = nullptr;
CGoStringFunc g_runXrayFromJson = nullptr;
CGoStopFunc g_stopXray = nullptr;
CGoPingFunc g_pingXray = nullptr;
CGoSetTunFdFunc g_setTunFd = nullptr;
// Optional symbols. Resolved lazily and best-effort: an older libxray.so that
// does not export these (e.g. built before they were added to the version
// script) leaves them null and the bridge degrades gracefully.
CGoStringFunc g_queryStats = nullptr;
CGoStringFunc g_testXray = nullptr;
CGoVersionFunc g_xrayVersion = nullptr;
CGoStringFunc g_countGeoData = nullptr;
CGoStringFunc g_readGeoFiles = nullptr;
CGoFreePortsFunc g_getFreePorts = nullptr;
CGoStringFunc g_convertShareLinksToXrayJson = nullptr;
CGoStringFunc g_convertXrayJsonToShareLinks = nullptr;

// sing-box second core state. Implementation lives in the sing-box block below;
// declared here so GetStats (above that block) can read g_singboxRunning.
std::atomic_bool g_singboxRunning(false);
void* g_singboxHandle = nullptr;
CGoStringFunc g_singboxStart = nullptr;
CGoStopFunc g_singboxStop = nullptr;
CGoSetTunFdFunc g_singboxSetTunFd = nullptr;

// tun2socks 适配器（libheytun2socks.so）：把 Harmony VPN TUN fd 的流量转发到
// Xray 的本地 SOCKS 入站（fd:// -> socks5://127.0.0.1:port）。与 libxray.so 分开
// 编译/加载——各自独立的 Go 运行时 + TLSDESC，规避 xray-core 与 tun2socks 的
// gvisor 版本冲突。
using Tun2SocksStartFunc = int (*)(int, char*, int, int);
using Tun2SocksStopFunc = void (*)();
using Tun2SocksStatsFunc = int64_t (*)();
void* g_tun2socksHandle = nullptr;
Tun2SocksStartFunc g_startTun2Socks = nullptr;
Tun2SocksStopFunc g_stopTun2Socks = nullptr;
Tun2SocksStatsFunc g_tun2SocksUploadBytes = nullptr;
Tun2SocksStatsFunc g_tun2SocksDownloadBytes = nullptr;

// hev-socks5-tunnel 引擎（libhevsocks5tun.so）：「使用 Hev TUN 引擎」开关打开时的高性能
// 数据面，对照默认 gvisor 的 libheytun2socks.so。hev 是纯 C：main 阻塞（跑到 quit 才返回），
// 所以必须放到独立线程跑；stats 是 (tx_pkts, tx_bytes, rx_pkts, rx_bytes) 四个出参。
using HevStartFunc = int (*)(const unsigned char*, unsigned int, int);
using HevQuitFunc = void (*)();
using HevStatsFunc = void (*)(size_t*, size_t*, size_t*, size_t*);
void* g_hevHandle = nullptr;
HevStartFunc g_hevStart = nullptr;
HevQuitFunc g_hevQuit = nullptr;
HevStatsFunc g_hevStats = nullptr;
std::thread g_hevThread;

// 当前 TUN 数据面引擎：0=无，1=gvisor(tun2socks)，2=hev。stop/stats 据此分发。
constexpr int TUN_ENGINE_NONE = 0;
constexpr int TUN_ENGINE_GVISOR = 1;
constexpr int TUN_ENGINE_HEV = 2;
std::atomic<int> g_tunEngine(TUN_ENGINE_NONE);

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

std::string ErrnoMessage(const std::string& prefix, int errorCode = errno)
{
    return prefix + ": " + std::strerror(errorCode);
}

std::string DirName(const std::string& path)
{
    size_t slash = path.find_last_of('/');
    if (slash == std::string::npos || slash == 0) {
        return ".";
    }
    return path.substr(0, slash);
}

std::string NativeLibDir()
{
    Dl_info info;
    if (dladdr(reinterpret_cast<void*>(&LogInfo), &info) != 0 && info.dli_fname != nullptr) {
        return DirName(info.dli_fname);
    }
    return ".";
}

std::string ExecPath(const std::string& name)
{
    return NativeLibDir() + "/" + name;
}

bool WriteTextFile(const std::string& path, const std::string& content, std::string& message)
{
    FILE* file = std::fopen(path.c_str(), "wb");
    if (file == nullptr) {
        message = ErrnoMessage("Failed to open file for writing: " + path);
        return false;
    }

    size_t written = std::fwrite(content.data(), 1, content.size(), file);
    std::fclose(file);
    if (written != content.size()) {
        message = ErrnoMessage("Failed to write complete file: " + path);
        return false;
    }
    return true;
}

bool MakeFdInheritable(int fd, std::string& message)
{
    int flags = fcntl(fd, F_GETFD);
    if (flags < 0) {
        message = ErrnoMessage("fcntl(F_GETFD) failed for TUN fd");
        return false;
    }
    if (fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC) < 0) {
        message = ErrnoMessage("fcntl(F_SETFD) failed for TUN fd");
        return false;
    }
    return true;
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

// Like CreateResult but does not mutate g_lastMessage or log. Used by the
// auxiliary query functions (stats/test/version) so they never clobber the
// connection runtime state that getStats() reports.
napi_value CreateResultQuiet(napi_env env, bool ok, const std::string& message)
{
    napi_value result = nullptr;
    napi_create_object(env, &result);
    napi_set_named_property(env, result, "ok", CreateBool(env, ok));
    napi_set_named_property(env, result, "message", CreateString(env, message));
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

// Decodes a libXray CGo return value (base64 of a CallResponse JSON
// {"success":bool,"data":...,"err":string}) and reports it back to ArkTS as
// {ok, message} where message is the decoded CallResponse JSON. Callers on the
// ArkTS side JSON.parse the message to read `data`/`err`. Frees the raw pointer
// returned by the Go c-shared library.
napi_value BuildCallResult(napi_env env, char* raw, const std::string& nullMessage)
{
    if (raw == nullptr) {
        return CreateResultQuiet(env, false, nullMessage);
    }
    std::string response(raw);
    std::free(raw);

    std::string decoded = Base64Decode(response);
    if (decoded.find('{') == std::string::npos) {
        decoded = response;
    }
    bool ok = decoded.find("\"success\":true") != std::string::npos;
    return CreateResultQuiet(env, ok, decoded);
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

bool LoadXrayCore(std::string& message);

bool LoadXray()
{
    std::string message;
    bool ok = LoadXrayCore(message);
    if (!ok) {
        g_lastMessage = message;
        LogError(message);
    }
    return ok;
}

bool LoadXrayCore(std::string& message)
{
    if (g_xrayHandle != nullptr && g_runXrayFromJson != nullptr && g_stopXray != nullptr &&
        g_pingXray != nullptr && g_setTunFd != nullptr) {
        return true;
    }

    void* handle = dlopen(ExecPath(XRAY_CORE_LIB).c_str(), RTLD_LAZY | RTLD_LOCAL);
    if (handle == nullptr) {
        handle = dlopen(XRAY_CORE_LIB, RTLD_LAZY | RTLD_LOCAL);
    }
    if (handle == nullptr) {
        const char* error = dlerror();
        message = std::string("libXray unavailable: failed to load ") + XRAY_CORE_LIB + ": " +
            (error != nullptr ? error : "unknown error");
        return false;
    }

    dlerror();
    g_runXrayFromJson = reinterpret_cast<CGoStringFunc>(dlsym(handle, "CGoRunXrayFromJSON"));
    g_stopXray = reinterpret_cast<CGoStopFunc>(dlsym(handle, "CGoStopXray"));
    g_pingXray = reinterpret_cast<CGoPingFunc>(dlsym(handle, "CGoPing"));
    // CGoSetTunFd 为可选：tun2socks（SOCKS 入站）数据面不需要它，SOCKS 版
    // libxray.so 也不导出它。只把真正必需的三个符号作为加载成功判据。
    g_setTunFd = reinterpret_cast<CGoSetTunFdFunc>(dlsym(handle, "CGoSetTunFd"));
    if (g_runXrayFromJson == nullptr || g_stopXray == nullptr || g_pingXray == nullptr) {
        message = "libXray unavailable: required CGo symbols missing.";
        return false;
    }
    g_xrayHandle = handle;
    return true;
}

// 懒加载 libheytun2socks.so 并解析 HeyTun2Socks* 符号。独立 handle、独立 Go 运行时。
constexpr const char* TUN2SOCKS_LIB = "libheytun2socks.so";

bool LoadTun2SocksCore(std::string& message)
{
    if (g_tun2socksHandle != nullptr && g_startTun2Socks != nullptr && g_stopTun2Socks != nullptr) {
        return true;
    }
    void* handle = dlopen(ExecPath(TUN2SOCKS_LIB).c_str(), RTLD_LAZY | RTLD_LOCAL);
    if (handle == nullptr) {
        handle = dlopen(TUN2SOCKS_LIB, RTLD_LAZY | RTLD_LOCAL);
    }
    if (handle == nullptr) {
        const char* error = dlerror();
        message = std::string("tun2socks unavailable: failed to load ") + TUN2SOCKS_LIB + ": " +
            (error != nullptr ? error : "unknown error");
        return false;
    }
    dlerror();
    g_startTun2Socks = reinterpret_cast<Tun2SocksStartFunc>(dlsym(handle, "HeyTun2SocksStart"));
    g_stopTun2Socks = reinterpret_cast<Tun2SocksStopFunc>(dlsym(handle, "HeyTun2SocksStop"));
    g_tun2SocksUploadBytes = reinterpret_cast<Tun2SocksStatsFunc>(dlsym(handle, "HeyTun2SocksUploadBytes"));
    g_tun2SocksDownloadBytes = reinterpret_cast<Tun2SocksStatsFunc>(dlsym(handle, "HeyTun2SocksDownloadBytes"));
    if (g_startTun2Socks == nullptr || g_stopTun2Socks == nullptr) {
        message = "tun2socks unavailable: required HeyTun2Socks symbols missing.";
        return false;
    }
    g_tun2socksHandle = handle;
    return true;
}

// 懒加载 libhevsocks5tun.so 并解析 hev_socks5_tunnel_* 符号。独立 handle。
constexpr const char* HEV_TUN_LIB = "libhevsocks5tun.so";

bool LoadHevCore(std::string& message)
{
    if (g_hevHandle != nullptr && g_hevStart != nullptr && g_hevQuit != nullptr) {
        return true;
    }
    void* handle = dlopen(ExecPath(HEV_TUN_LIB).c_str(), RTLD_LAZY | RTLD_LOCAL);
    if (handle == nullptr) {
        handle = dlopen(HEV_TUN_LIB, RTLD_LAZY | RTLD_LOCAL);
    }
    if (handle == nullptr) {
        const char* error = dlerror();
        message = std::string("hev tun unavailable: failed to load ") + HEV_TUN_LIB + ": " +
            (error != nullptr ? error : "unknown error");
        return false;
    }
    dlerror();
    g_hevStart = reinterpret_cast<HevStartFunc>(dlsym(handle, "hev_socks5_tunnel_main_from_str"));
    g_hevQuit = reinterpret_cast<HevQuitFunc>(dlsym(handle, "hev_socks5_tunnel_quit"));
    g_hevStats = reinterpret_cast<HevStatsFunc>(dlsym(handle, "hev_socks5_tunnel_stats"));
    if (g_hevStart == nullptr || g_hevQuit == nullptr) {
        message = "hev tun unavailable: required hev_socks5_tunnel symbols missing.";
        return false;
    }
    g_hevHandle = handle;
    return true;
}

CGoPingFunc LoadCGoPing(std::string& message)
{
    if (!LoadXrayCore(message)) {
        message = "libXray ping unavailable: " + message;
        return nullptr;
    }
    return g_pingXray;
}

// Best-effort resolution of an optional symbol from the already-loaded core.
// Returns nullptr (without failing the core) when the symbol is not exported.
void* LoadOptionalSymbol(const char* name)
{
    std::string message;
    if (!LoadXrayCore(message) || g_xrayHandle == nullptr) {
        return nullptr;
    }
    dlerror();
    return dlsym(g_xrayHandle, name);
}

CGoStringFunc LoadQueryStats()
{
    if (g_queryStats == nullptr) {
        g_queryStats = reinterpret_cast<CGoStringFunc>(LoadOptionalSymbol("CGoQueryStats"));
    }
    return g_queryStats;
}

CGoStringFunc LoadTestXray()
{
    if (g_testXray == nullptr) {
        g_testXray = reinterpret_cast<CGoStringFunc>(LoadOptionalSymbol("CGoTestXray"));
    }
    return g_testXray;
}

CGoVersionFunc LoadXrayVersion()
{
    if (g_xrayVersion == nullptr) {
        g_xrayVersion = reinterpret_cast<CGoVersionFunc>(LoadOptionalSymbol("CGoXrayVersion"));
    }
    return g_xrayVersion;
}

CGoStringFunc LoadCountGeoData()
{
    if (g_countGeoData == nullptr) {
        g_countGeoData = reinterpret_cast<CGoStringFunc>(LoadOptionalSymbol("CGoCountGeoData"));
    }
    return g_countGeoData;
}

CGoStringFunc LoadReadGeoFiles()
{
    if (g_readGeoFiles == nullptr) {
        g_readGeoFiles = reinterpret_cast<CGoStringFunc>(LoadOptionalSymbol("CGoReadGeoFiles"));
    }
    return g_readGeoFiles;
}

CGoFreePortsFunc LoadGetFreePorts()
{
    if (g_getFreePorts == nullptr) {
        g_getFreePorts = reinterpret_cast<CGoFreePortsFunc>(LoadOptionalSymbol("CGoGetFreePorts"));
    }
    return g_getFreePorts;
}

CGoStringFunc LoadConvertShareLinksToXrayJson()
{
    if (g_convertShareLinksToXrayJson == nullptr) {
        g_convertShareLinksToXrayJson =
            reinterpret_cast<CGoStringFunc>(LoadOptionalSymbol("CGoConvertShareLinksToXrayJson"));
    }
    return g_convertShareLinksToXrayJson;
}

CGoStringFunc LoadConvertXrayJsonToShareLinks()
{
    if (g_convertXrayJsonToShareLinks == nullptr) {
        g_convertXrayJsonToShareLinks =
            reinterpret_cast<CGoStringFunc>(LoadOptionalSymbol("CGOConvertXrayJsonToShareLinks"));
    }
    return g_convertXrayJsonToShareLinks;
}

bool ParsePingResponse(const std::string& json, int64_t& delay, std::string& message)
{
    delay = -1;
    bool success = json.find("\"success\":true") != std::string::npos;

    size_t dataKey = json.find("\"data\":");
    if (dataKey != std::string::npos) {
        size_t start = dataKey + 7;
        while (start < json.size() && (json[start] == ' ' || json[start] == '"')) {
            start++;
        }
        size_t end = start;
        while (end < json.size() && (std::isdigit(static_cast<unsigned char>(json[end])) != 0 || json[end] == '-')) {
            end++;
        }
        if (end > start) {
            delay = std::strtoll(json.substr(start, end - start).c_str(), nullptr, 10);
        }
    }

    if (success && delay >= 0) {
        message = "libXray ping ok.";
        return true;
    }

    size_t errorKey = json.find("\"err\":\"");
    if (errorKey != std::string::npos) {
        size_t start = errorKey + 7;
        size_t end = json.find('"', start);
        std::string error = json.substr(start, end == std::string::npos ? std::string::npos : end - start);
        message = error.empty() ? "libXray ping failed." : error;
    } else {
        message = success ? "libXray ping returned no delay." : "libXray ping failed.";
    }
    return false;
}

napi_value CreatePingResult(napi_env env, bool ok, int64_t delayMs, const std::string& message)
{
    napi_value result = nullptr;
    napi_create_object(env, &result);
    napi_set_named_property(env, result, "ok", CreateBool(env, ok));
    napi_set_named_property(env, result, "delayMs", CreateInt64(env, delayMs));
    napi_set_named_property(env, result, "message", CreateString(env, message));
    if (ok) {
        LogInfo(message);
    } else {
        LogWarn(message);
    }
    return result;
}

napi_value PingOutbound(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 4) {
        return CreatePingResult(env, false, -1, "Missing ping arguments.");
    }

    std::string config = GetStringArg(env, args[0]);
    std::string datDir = GetStringArg(env, args[1]);
    std::string url = GetStringArg(env, args[2]);
    int32_t timeoutSeconds = GetIntArg(env, args[3]);
    std::string proxy = argc >= 5 ? GetStringArg(env, args[4]) : "socks5://127.0.0.1:10825";

    if (config.empty()) {
        return CreatePingResult(env, false, -1, "Ping config JSON is empty.");
    }
    if (datDir.empty()) {
        return CreatePingResult(env, false, -1, "Ping requires a data directory.");
    }
    if (url.empty()) {
        return CreatePingResult(env, false, -1, "Ping requires a test URL.");
    }
    if (timeoutSeconds <= 0) {
        timeoutSeconds = 10;
    }

    std::string message;
    CGoPingFunc ping = LoadCGoPing(message);
    if (ping == nullptr) {
        return CreatePingResult(env, false, -1, message);
    }

    // 并发测速时每个 ping 用独立的 socks 端口，按端口区分配置文件名，避免多个并发
    // ping 同时写同一个文件互相覆盖（旧实现固定 PING_CONFIG_FILE 会造成串行/串读）。
    std::string portDigits;
    size_t colonPos = proxy.find_last_of(':');
    if (colonPos != std::string::npos) {
        for (size_t i = colonPos + 1; i < proxy.size(); ++i) {
            char c = proxy[i];
            if (c >= '0' && c <= '9') {
                portDigits.push_back(c);
            }
        }
    }
    std::string configFile = portDigits.empty() ? std::string(PING_CONFIG_FILE) : ("hey-ping-" + portDigits + ".json");
    std::string configPath = datDir + "/" + configFile;
    if (!WriteTextFile(configPath, config, message)) {
        return CreatePingResult(env, false, -1, message);
    }

    std::ostringstream request;
    request << "{\"datDir\":\"" << JsonEscape(datDir) << "\","
            << "\"configPath\":\"" << JsonEscape(configPath) << "\","
            << "\"timeout\":" << timeoutSeconds << ","
            << "\"url\":\"" << JsonEscape(url) << "\","
            << "\"proxy\":\"" << JsonEscape(proxy) << "\"}";

    std::string encoded = Base64Encode(request.str());
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = ping(buffer.data());
    if (raw == nullptr) {
        return CreatePingResult(env, false, -1, "libXray ping returned null.");
    }

    std::string response(raw);
    std::string decoded = Base64Decode(response);
    if (decoded.find('{') == std::string::npos) {
        decoded = response;
    }

    int64_t delay = -1;
    bool ok = ParsePingResponse(decoded, delay, message);
    return CreatePingResult(env, ok, delay, message);
}

// Queries the running Xray metrics endpoint. `server` is the expvar URL, e.g.
// "http://127.0.0.1:10845/debug/vars". libXray's CGoQueryStats simply HTTP GETs
// it and wraps the body in a CallResponse; the body (Go expvar JSON containing
// the per-tag stats) is returned to ArkTS as the result message for parsing.
napi_value QueryStats(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResultQuiet(env, false, "Missing stats server.");
    }

    std::string server = GetStringArg(env, args[0]);
    if (server.empty()) {
        return CreateResultQuiet(env, false, "Stats server is empty.");
    }

    CGoStringFunc query = LoadQueryStats();
    if (query == nullptr) {
        return CreateResultQuiet(env, false, "Stats unavailable: CGoQueryStats not exported by libXray.");
    }

    std::string encoded = Base64Encode(server);
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = query(buffer.data());
    return BuildCallResult(env, raw, "CGoQueryStats returned null.");
}

// Pre-connect config validation. Writes the generated config to a file and asks
// libXray to instantiate (but not start) the core, surfacing config errors
// before the VPN tunnel is created. Degrades to success when CGoTestXray is not
// exported so it never blocks startup on an older core build.
napi_value TestXrayConfig(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return CreateResultQuiet(env, false, "Missing test arguments.");
    }

    std::string config = GetStringArg(env, args[0]);
    std::string workDir = GetStringArg(env, args[1]);
    if (config.empty()) {
        return CreateResultQuiet(env, false, "Test config JSON is empty.");
    }
    if (workDir.empty()) {
        return CreateResultQuiet(env, false, "Test requires a work directory.");
    }
    if (config.find("\"inbounds\"") == std::string::npos || config.find("\"outbounds\"") == std::string::npos) {
        return CreateResultQuiet(env, false, "Generated Xray config must contain inbounds and outbounds.");
    }

    CGoStringFunc test = LoadTestXray();
    if (test == nullptr) {
        return CreateResultQuiet(env, true, "Preflight skipped: CGoTestXray not exported by libXray.");
    }

    std::string message;
    std::string configPath = workDir + "/" + TEST_CONFIG_FILE;
    if (!WriteTextFile(configPath, config, message)) {
        return CreateResultQuiet(env, false, message);
    }

    std::ostringstream request;
    request << "{\"datDir\":\"" << JsonEscape(workDir) << "\","
            << "\"configPath\":\"" << JsonEscape(configPath) << "\"}";
    std::string encoded = Base64Encode(request.str());
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = test(buffer.data());
    return BuildCallResult(env, raw, "CGoTestXray returned null.");
}

// Returns the bundled Xray core version (CallResponse with the version string in
// `data`). Degrades to ok=false when CGoXrayVersion is not exported.
napi_value XrayVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    CGoVersionFunc version = LoadXrayVersion();
    if (version == nullptr) {
        return CreateResultQuiet(env, false, "Xray version unavailable: CGoXrayVersion not exported by libXray.");
    }
    char* raw = version();
    return BuildCallResult(env, raw, "CGoXrayVersion returned null.");
}

// Counts a geosite/geoip .dat file and lets libXray write the sidecar
// {name}.json into datDir. Request shape matches libXray CountGeoDataRequest:
// {"datDir": "...", "name": "geosite|geoip", "geoType": "domain|ip"}.
napi_value CountGeoData(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3) {
        return CreateResultQuiet(env, false, "Missing geo count arguments.");
    }

    std::string datDir = GetStringArg(env, args[0]);
    std::string name = GetStringArg(env, args[1]);
    std::string geoType = GetStringArg(env, args[2]);
    if (datDir.empty()) {
        return CreateResultQuiet(env, false, "Geo data directory is empty.");
    }
    if (name.empty()) {
        return CreateResultQuiet(env, false, "Geo data file name is empty.");
    }
    if (geoType != "domain" && geoType != "ip") {
        return CreateResultQuiet(env, false, "Geo data type must be domain or ip.");
    }

    CGoStringFunc count = LoadCountGeoData();
    if (count == nullptr) {
        return CreateResultQuiet(env, false, "Geo count unavailable: CGoCountGeoData not exported by libXray.");
    }

    std::ostringstream request;
    request << "{\"datDir\":\"" << JsonEscape(datDir) << "\","
            << "\"name\":\"" << JsonEscape(name) << "\","
            << "\"geoType\":\"" << JsonEscape(geoType) << "\"}";
    std::string encoded = Base64Encode(request.str());
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = count(buffer.data());
    return BuildCallResult(env, raw, "CGoCountGeoData returned null.");
}

// Reads geo resource references from an Xray config JSON. libXray returns a
// CallResponse whose data is {domain:["geosite.dat"], ip:["geoip.dat"]}.
napi_value ReadGeoFiles(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResultQuiet(env, false, "Missing Xray config JSON.");
    }

    std::string config = GetStringArg(env, args[0]);
    if (config.empty()) {
        return CreateResultQuiet(env, false, "Xray config JSON is empty.");
    }

    CGoStringFunc read = LoadReadGeoFiles();
    if (read == nullptr) {
        return CreateResultQuiet(env, false, "Geo file reader unavailable: CGoReadGeoFiles not exported by libXray.");
    }

    std::string encoded = Base64Encode(config);
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = read(buffer.data());
    return BuildCallResult(env, raw, "CGoReadGeoFiles returned null.");
}

// Requests free localhost TCP ports from libXray/nodep. The result message is a
// CallResponse whose data is {ports:[...]}.
napi_value GetFreePorts(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResultQuiet(env, false, "Missing free-port count.");
    }

    int32_t count = GetIntArg(env, args[0]);
    if (count <= 0) {
        return CreateResultQuiet(env, false, "Free-port count must be positive.");
    }
    if (count > 16) {
        count = 16;
    }

    CGoFreePortsFunc getFreePorts = LoadGetFreePorts();
    if (getFreePorts == nullptr) {
        return CreateResultQuiet(env, false, "Free ports unavailable: CGoGetFreePorts not exported by libXray.");
    }

    char* raw = getFreePorts(static_cast<int64_t>(count));
    return BuildCallResult(env, raw, "CGoGetFreePorts returned null.");
}

// Converts v2rayN plain/base64 share text, Xray JSON, or Clash.Meta YAML to a
// full Xray JSON config through libXray. ArkTS extracts the returned outbounds
// and stores them as manual nodes.
napi_value ConvertShareLinksToXrayJson(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResultQuiet(env, false, "Missing share text.");
    }

    std::string text = GetStringArg(env, args[0]);
    if (text.empty()) {
        return CreateResultQuiet(env, false, "Share text is empty.");
    }

    CGoStringFunc convert = LoadConvertShareLinksToXrayJson();
    if (convert == nullptr) {
        return CreateResultQuiet(
            env, false, "Share conversion unavailable: CGoConvertShareLinksToXrayJson not exported by libXray.");
    }

    std::string encoded = Base64Encode(text);
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = convert(buffer.data());
    return BuildCallResult(env, raw, "CGoConvertShareLinksToXrayJson returned null.");
}

// Converts a full Xray JSON config to share links through libXray. Kept as a
// best-effort bridge for export/share fallbacks; unsupported outbound protocols
// are skipped by libXray.
napi_value ConvertXrayJsonToShareLinks(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResultQuiet(env, false, "Missing Xray config JSON.");
    }

    std::string config = GetStringArg(env, args[0]);
    if (config.empty()) {
        return CreateResultQuiet(env, false, "Xray config JSON is empty.");
    }

    CGoStringFunc convert = LoadConvertXrayJsonToShareLinks();
    if (convert == nullptr) {
        return CreateResultQuiet(
            env, false, "Share export unavailable: CGOConvertXrayJsonToShareLinks not exported by libXray.");
    }

    std::string encoded = Base64Encode(config);
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = convert(buffer.data());
    return BuildCallResult(env, raw, "CGOConvertXrayJsonToShareLinks returned null.");
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

napi_value SetTunFd(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResult(env, false, "Missing TUN fd.");
    }

    int32_t tunFd = GetIntArg(env, args[0]);
    if (tunFd < 0) {
        return CreateResult(env, false, "Invalid TUN fd.");
    }
    if (g_xrayRunning.load()) {
        return CreateResult(env, false, "Cannot set TUN fd while Xray is running.");
    }

    std::string message;
    if (!LoadXrayCore(message)) {
        g_tunRunning.store(false);
        return CreateResult(env, false, message);
    }
    if (!MakeFdInheritable(tunFd, message)) {
        g_tunRunning.store(false);
        return CreateResult(env, false, message);
    }

    g_uploadBytes.store(0);
    g_downloadBytes.store(0);
    g_setTunFd(tunFd);
    g_tunRunning.store(true);
    return CreateResult(env, true, "Xray TUN fd configured.");
}

napi_value StartXray(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
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

    std::string workDir = argc >= 2 ? GetStringArg(env, args[1]) : "";
    if (workDir.empty()) {
        return CreateResult(env, false, "Missing native work directory for Xray config.");
    }

    std::string message;
    if (!LoadXrayCore(message)) {
        g_xrayRunning.store(false);
        return CreateResult(env, false, message);
    }

    std::ostringstream request;
    request << "{\"datDir\":\"" << JsonEscape(workDir) << "\","
            << "\"configJSON\":\"" << JsonEscape(config) << "\"}";
    std::string encoded = Base64Encode(request.str());
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = g_runXrayFromJson(buffer.data());
    if (raw == nullptr) {
        g_xrayRunning.store(false);
        return CreateResult(env, false, "libXray run returned null.");
    }

    std::string response(raw);
    std::free(raw);
    if (!ResponseOk(response, message)) {
        g_xrayRunning.store(false);
        return CreateResult(env, false, message);
    }

    g_xrayRunning.store(true);
    return CreateResult(env, true, "Xray core started.");
}

napi_value StopXray(napi_env env, napi_callback_info info)
{
    (void)info;
    if (!g_xrayRunning.load()) {
        g_tunRunning.store(false);
        return CreateResult(env, true, "Xray already stopped.");
    }

    std::string message;
    if (!LoadXrayCore(message)) {
        return CreateResult(env, false, message);
    }

    char* raw = g_stopXray();
    if (raw == nullptr) {
        return CreateResult(env, false, "libXray stop returned null.");
    }
    std::string response(raw);
    std::free(raw);
    if (!ResponseOk(response, message)) {
        return CreateResult(env, false, message);
    }

    g_xrayRunning.store(false);
    g_tunRunning.store(false);
    return CreateResult(env, true, "Xray core stopped.");
}

napi_value GetStats(napi_env env, napi_callback_info info)
{
    (void)info;

    napi_value result = nullptr;
    napi_create_object(env, &result);
    // TUN 数据面运行时，用当前引擎的字节计数刷新流量统计（仅在已加载引擎的 VPN 扩展
    // 进程里命中；主进程指针为 null，自动跳过）。注：这只是兜底，真实分流量优先取
    // queryNativeTraffic（Xray metrics）。
    if (g_tunRunning.load()) {
        const int engine = g_tunEngine.load();
        if (engine == TUN_ENGINE_HEV && g_hevStats != nullptr) {
            // hev_socks5_tunnel_stats(tx_pkts, tx_bytes, rx_pkts, rx_bytes)，相对 TUN 网卡：
            // tx=从 TUN 收到上行、rx=回写 TUN 的下行。若真机方向相反，调换这两行即可。
            size_t txPackets = 0;
            size_t txBytes = 0;
            size_t rxPackets = 0;
            size_t rxBytes = 0;
            g_hevStats(&txPackets, &txBytes, &rxPackets, &rxBytes);
            g_uploadBytes.store(static_cast<int64_t>(txBytes));
            g_downloadBytes.store(static_cast<int64_t>(rxBytes));
        } else if (g_tun2SocksUploadBytes != nullptr && g_tun2SocksDownloadBytes != nullptr) {
            g_uploadBytes.store(g_tun2SocksUploadBytes());
            g_downloadBytes.store(g_tun2SocksDownloadBytes());
        }
    }
    napi_set_named_property(env, result, "uploadBytes", CreateInt64(env, g_uploadBytes.load()));
    napi_set_named_property(env, result, "downloadBytes", CreateInt64(env, g_downloadBytes.load()));
    napi_set_named_property(env, result, "xrayRunning", CreateBool(env, g_xrayRunning.load() || g_singboxRunning.load()));
    napi_set_named_property(env, result, "tunRunning", CreateBool(env, g_tunRunning.load()));
    napi_set_named_property(env, result, "lastMessage", CreateString(env, g_lastMessage));
    return result;
}

// 启动 tun2socks 适配器：把 TUN fd 的流量转发到 socks5://host:port。必须在 Xray 的
// SOCKS 入站已监听之后调用。
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

    std::string message;
    if (!LoadTun2SocksCore(message)) {
        g_lastMessage = message;
        LogError(message);
        return CreateResult(env, false, message);
    }
    if (!MakeFdInheritable(tunFd, message)) {
        return CreateResult(env, false, message);
    }

    int result = g_startTun2Socks(tunFd, const_cast<char*>(host.c_str()), port, mtu);
    if (result != 0) {
        return CreateResult(env, false, "tun2socks adapter start failed.");
    }
    g_tunRunning.store(true);
    g_tunEngine.store(TUN_ENGINE_GVISOR);
    return CreateResult(env, true, "tun2socks adapter started.");
}

// 启动 hev-socks5-tunnel 引擎：把 TUN fd 的流量按 yaml 配置转发到本地 SOCKS。与
// StartTun2Socks 互斥（同一时刻只跑一条数据面）。hev 的 main 阻塞，放到独立线程。
napi_value StartHevTun(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return CreateResult(env, false, "Missing hev tun arguments.");
    }
    int32_t tunFd = GetIntArg(env, args[0]);
    std::string configYaml = GetStringArg(env, args[1]);
    if (tunFd < 0) {
        return CreateResult(env, false, "Invalid TUN fd.");
    }
    if (configYaml.empty()) {
        return CreateResult(env, false, "Empty hev tun config.");
    }
    if (g_tunRunning.load()) {
        return CreateResult(env, true, "tun data plane already running.");
    }
    g_uploadBytes.store(0);
    g_downloadBytes.store(0);

    std::string message;
    if (!LoadHevCore(message)) {
        g_lastMessage = message;
        LogError(message);
        return CreateResult(env, false, message);
    }
    if (!MakeFdInheritable(tunFd, message)) {
        return CreateResult(env, false, message);
    }

    // hev_socks5_tunnel_main_from_str 阻塞到 quit；起独立线程跑它。注意：配置解析失败时
    // 它会立刻返回（非阻塞），此处无法同步拿到该错误，只能靠日志/统计为 0 旁证。
    if (g_hevThread.joinable()) {
        g_hevThread.join();
    }
    HevStartFunc start = g_hevStart;
    g_hevThread = std::thread([start, configYaml, tunFd]() {
        start(reinterpret_cast<const unsigned char*>(configYaml.c_str()),
            static_cast<unsigned int>(configYaml.size()), tunFd);
    });
    g_tunRunning.store(true);
    g_tunEngine.store(TUN_ENGINE_HEV);
    return CreateResult(env, true, "hev tun engine started.");
}

napi_value StopTun2Socks(napi_env env, napi_callback_info info)
{
    (void)info;
    if (!g_tunRunning.load()) {
        return CreateResult(env, true, "tun data plane already stopped.");
    }
    const int engine = g_tunEngine.exchange(TUN_ENGINE_NONE);
    g_tunRunning.store(false);
    if (engine == TUN_ENGINE_HEV) {
        // hev：quit 让阻塞的 main 返回，再 join 回收线程。
        if (g_hevQuit != nullptr) {
            g_hevQuit();
        }
        if (g_hevThread.joinable()) {
            g_hevThread.join();
        }
        return CreateResult(env, true, "hev tun stop requested.");
    }
    // gvisor：engine.Stop() 可能阻塞，放到分离线程避免卡住 ArkTS 调用线程。
    std::string message;
    if (!LoadTun2SocksCore(message)) {
        return CreateResult(env, false, message);
    }
    Tun2SocksStopFunc stop = g_stopTun2Socks;
    std::thread([stop]() { stop(); }).detach();
    return CreateResult(env, true, "tun2socks stop requested.");
}

// ===================== sing-box second core (optional, preview) =====================
// libsingbox.so 是 sing-box 内核的 c-shared 封装（见 libsingbox/）。与上面的 Xray 核
// 平行：start/stop/setTunFd 必须从 VPN 原生线程调用（GOOS=android 下唯一安全的
// cgo->Go 上下文）。SingboxProbe 只 dlopen+dlsym、不触发 cgo，UI 线程点按也安全。
constexpr const char* SINGBOX_CORE_LIB = "libsingbox.so";

void* OpenSingbox(std::string& message)
{
    void* handle = dlopen(ExecPath(SINGBOX_CORE_LIB).c_str(), RTLD_LAZY | RTLD_LOCAL);
    if (handle == nullptr) {
        handle = dlopen(SINGBOX_CORE_LIB, RTLD_LAZY | RTLD_LOCAL);
    }
    if (handle == nullptr) {
        const char* error = dlerror();
        message = std::string("dlopen ") + SINGBOX_CORE_LIB + " failed: " +
            (error != nullptr ? error : "unknown error");
    }
    return handle;
}

// 懒加载 libsingbox.so 并解析生命周期符号。只应从 VPN 原生线程调用。
bool LoadSingboxCore(std::string& message)
{
    if (g_singboxHandle != nullptr && g_singboxStart != nullptr && g_singboxStop != nullptr &&
        g_singboxSetTunFd != nullptr) {
        return true;
    }
    void* handle = OpenSingbox(message);
    if (handle == nullptr) {
        return false;
    }
    dlerror();
    g_singboxStart = reinterpret_cast<CGoStringFunc>(dlsym(handle, "CGoStartSingBox"));
    g_singboxStop = reinterpret_cast<CGoStopFunc>(dlsym(handle, "CGoStopSingBox"));
    g_singboxSetTunFd = reinterpret_cast<CGoSetTunFdFunc>(dlsym(handle, "CGoSetTunFd"));
    if (g_singboxStart == nullptr || g_singboxStop == nullptr || g_singboxSetTunFd == nullptr) {
        message = "libsingbox unavailable: required CGo symbols missing.";
        return false;
    }
    g_singboxHandle = handle;
    return true;
}

// 诊断用：只 dlopen+dlsym，不触发 cgo，UI 线程安全（关于页探测按钮用）。
napi_value SingboxProbe(napi_env env, napi_callback_info info)
{
    (void)info;
    std::string message;
    void* handle = OpenSingbox(message);
    if (handle == nullptr) {
        return CreateResultQuiet(env, false, message);
    }
    dlerror();
    bool hasVersion = dlsym(handle, "CGoSingBoxVersion") != nullptr;
    bool hasStart = dlsym(handle, "CGoStartSingBox") != nullptr;
    bool hasStop = dlsym(handle, "CGoStopSingBox") != nullptr;
    bool hasSetTun = dlsym(handle, "CGoSetTunFd") != nullptr;
    std::ostringstream out;
    out << "libsingbox.so loaded. symbols: "
        << "Version=" << (hasVersion ? "yes" : "no")
        << " Start=" << (hasStart ? "yes" : "no")
        << " Stop=" << (hasStop ? "yes" : "no")
        << " SetTunFd=" << (hasSetTun ? "yes" : "no");
    bool ok = hasVersion && hasStart && hasStop && hasSetTun;
    return CreateResultQuiet(env, ok, out.str());
}

// 真调 CGoSingBoxVersion —— 仅限 VPN 原生线程（UI 线程冷调可能 SIGSEGV）。
napi_value SingboxVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    std::string message;
    void* handle = OpenSingbox(message);
    if (handle == nullptr) {
        return CreateResultQuiet(env, false, message);
    }
    dlerror();
    CGoVersionFunc version = reinterpret_cast<CGoVersionFunc>(dlsym(handle, "CGoSingBoxVersion"));
    if (version == nullptr) {
        return CreateResultQuiet(env, false, "CGoSingBoxVersion not exported by libsingbox.so.");
    }
    char* raw = version();
    return BuildCallResult(env, raw, "CGoSingBoxVersion returned null.");
}

napi_value SingboxSetTunFd(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResult(env, false, "Missing TUN fd.");
    }

    int32_t tunFd = GetIntArg(env, args[0]);
    if (tunFd < 0) {
        return CreateResult(env, false, "Invalid TUN fd.");
    }
    if (g_singboxRunning.load()) {
        return CreateResult(env, false, "Cannot set TUN fd while sing-box is running.");
    }

    std::string message;
    if (!LoadSingboxCore(message)) {
        g_tunRunning.store(false);
        return CreateResult(env, false, message);
    }
    if (!MakeFdInheritable(tunFd, message)) {
        g_tunRunning.store(false);
        return CreateResult(env, false, message);
    }

    g_uploadBytes.store(0);
    g_downloadBytes.store(0);
    // sing-box 自己管 tun：把 fd 存进 Go wrapper，CGoStartSingBox 时由 OpenTun 取用。
    g_singboxSetTunFd(tunFd);
    g_tunRunning.store(true);
    return CreateResult(env, true, "sing-box TUN fd configured.");
}

napi_value SingboxStart(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return CreateResult(env, false, "Missing sing-box config JSON.");
    }

    std::string config = GetStringArg(env, args[0]);
    if (config.empty()) {
        return CreateResult(env, false, "sing-box config JSON is empty.");
    }
    if (g_singboxRunning.load()) {
        return CreateResult(env, true, "sing-box already running.");
    }

    std::string workDir = argc >= 2 ? GetStringArg(env, args[1]) : "";
    if (workDir.empty()) {
        return CreateResult(env, false, "Missing native work directory for sing-box config.");
    }

    std::string message;
    if (!LoadSingboxCore(message)) {
        g_singboxRunning.store(false);
        return CreateResult(env, false, message);
    }

    // 请求体对齐 libsingbox/main.go 的 startRequest：{"basePath":..,"config":..}
    std::ostringstream request;
    request << "{\"basePath\":\"" << JsonEscape(workDir) << "\","
            << "\"config\":\"" << JsonEscape(config) << "\"}";
    std::string encoded = Base64Encode(request.str());
    std::vector<char> buffer(encoded.begin(), encoded.end());
    buffer.push_back('\0');

    char* raw = g_singboxStart(buffer.data());
    if (raw == nullptr) {
        g_singboxRunning.store(false);
        return CreateResult(env, false, "libsingbox start returned null.");
    }
    std::string response(raw);
    std::free(raw);
    if (!ResponseOk(response, message)) {
        g_singboxRunning.store(false);
        return CreateResult(env, false, message);
    }

    g_singboxRunning.store(true);
    return CreateResult(env, true, "sing-box core started.");
}

napi_value SingboxStop(napi_env env, napi_callback_info info)
{
    (void)info;
    if (!g_singboxRunning.load()) {
        g_tunRunning.store(false);
        return CreateResult(env, true, "sing-box already stopped.");
    }

    std::string message;
    if (!LoadSingboxCore(message)) {
        return CreateResult(env, false, message);
    }

    char* raw = g_singboxStop();
    if (raw == nullptr) {
        return CreateResult(env, false, "libsingbox stop returned null.");
    }
    std::string response(raw);
    std::free(raw);
    if (!ResponseOk(response, message)) {
        return CreateResult(env, false, message);
    }

    g_singboxRunning.store(false);
    g_tunRunning.store(false);
    return CreateResult(env, true, "sing-box core stopped.");
}
// =================== [end sing-box second core] ===================

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "validateConfig", nullptr, ValidateConfig, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setTunFd", nullptr, SetTunFd, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startXray", nullptr, StartXray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopXray", nullptr, StopXray, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getStats", nullptr, GetStats, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startTun2Socks", nullptr, StartTun2Socks, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startHevTun", nullptr, StartHevTun, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopTun2Socks", nullptr, StopTun2Socks, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pingOutbound", nullptr, PingOutbound, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "queryStats", nullptr, QueryStats, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "testXrayConfig", nullptr, TestXrayConfig, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "xrayVersion", nullptr, XrayVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "countGeoData", nullptr, CountGeoData, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "readGeoFiles", nullptr, ReadGeoFiles, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getFreePorts", nullptr, GetFreePorts, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "convertShareLinksToXrayJson", nullptr, ConvertShareLinksToXrayJson, nullptr, nullptr, nullptr,
            napi_default, nullptr },
        { "convertXrayJsonToShareLinks", nullptr, ConvertXrayJsonToShareLinks, nullptr, nullptr, nullptr,
            napi_default, nullptr },
        // sing-box second core (optional). singboxProbe is UI-thread safe (dlopen only);
        // the rest must be called from the VPN native thread.
        { "singboxProbe", nullptr, SingboxProbe, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "singboxVersion", nullptr, SingboxVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "singboxSetTunFd", nullptr, SingboxSetTunFd, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "singboxStart", nullptr, SingboxStart, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "singboxStop", nullptr, SingboxStop, nullptr, nullptr, nullptr, napi_default, nullptr },
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
