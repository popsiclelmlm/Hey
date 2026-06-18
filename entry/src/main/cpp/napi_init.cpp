#include "napi/native_api.h"

#include <atomic>
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
    g_setTunFd = reinterpret_cast<CGoSetTunFdFunc>(dlsym(handle, "CGoSetTunFd"));
    if (g_runXrayFromJson == nullptr || g_stopXray == nullptr || g_pingXray == nullptr || g_setTunFd == nullptr) {
        message = "libXray unavailable: required CGo symbols missing.";
        return false;
    }
    g_xrayHandle = handle;
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

    std::string configPath = datDir + "/" + PING_CONFIG_FILE;
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
    napi_set_named_property(env, result, "uploadBytes", CreateInt64(env, g_uploadBytes.load()));
    napi_set_named_property(env, result, "downloadBytes", CreateInt64(env, g_downloadBytes.load()));
    napi_set_named_property(env, result, "xrayRunning", CreateBool(env, g_xrayRunning.load()));
    napi_set_named_property(env, result, "tunRunning", CreateBool(env, g_tunRunning.load()));
    napi_set_named_property(env, result, "lastMessage", CreateString(env, g_lastMessage));
    return result;
}

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
        { "pingOutbound", nullptr, PingOutbound, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "queryStats", nullptr, QueryStats, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "testXrayConfig", nullptr, TestXrayConfig, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "xrayVersion", nullptr, XrayVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "countGeoData", nullptr, CountGeoData, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "readGeoFiles", nullptr, ReadGeoFiles, nullptr, nullptr, nullptr, napi_default, nullptr },
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
