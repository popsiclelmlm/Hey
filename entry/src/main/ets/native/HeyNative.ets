import heyNative from 'libheyvpn.so';
import { RuntimeStats } from '../core/Profile';

export interface NativeResult {
  ok: boolean;
  message: string;
}

export interface NativePingResult {
  ok: boolean;
  delayMs: number;
  message: string;
}

export interface NativeTrafficStats {
  ok: boolean;
  uploadBytes: number;
  downloadBytes: number;
  message: string;
}

export interface NativeGeoFilesResult {
  ok: boolean;
  domainFiles: Array<string>;
  ipFiles: Array<string>;
  message: string;
}

export interface NativeFreePortsResult {
  ok: boolean;
  ports: Array<number>;
  message: string;
}

export interface NativeXrayJsonResult {
  ok: boolean;
  configJson: string;
  message: string;
}

export interface NativeTextResult {
  ok: boolean;
  text: string;
  message: string;
}

// libXray wraps every CGo return value in a CallResponse. The native bridge
// decodes the base64 envelope and hands us the JSON below as the message.
interface CallResponseString {
  success: boolean;
  data: string;
  err: string;
}

interface CallResponseAny {
  success: boolean;
  data?: Object | string | number;
  err?: string;
}

// Shape of the Xray metrics expvar body (/debug/vars). Only the stats branch is
// relevant; counters are grouped type -> tag -> direction.
interface ExpvarStats {
  outbound?: Record<string, Record<string, number>>;
}

interface ExpvarRoot {
  stats?: ExpvarStats;
}

interface GeoFilesData {
  domain?: Array<string>;
  ip?: Array<string>;
}

interface FreePortsData {
  ports?: Array<number>;
}

interface NativeBridge {
  validateConfig(configJson: string): NativeResult;
  setTunFd(tunFd: number): NativeResult;
  startXray(configJson: string, workDir: string): NativeResult;
  stopXray(): NativeResult;
  getStats(): RuntimeStats;
  startTun2Socks(tunFd: number, socksHost: string, socksPort: number, mtu: number): NativeResult;
  startHevTun(tunFd: number, configYaml: string): NativeResult;
  stopTun2Socks(): NativeResult;
  pingOutbound(configJson: string, datDir: string, url: string, timeoutSeconds: number, proxy: string): NativePingResult;
  queryStats(server: string): NativeResult;
  testXrayConfig(configJson: string, workDir: string): NativeResult;
  xrayVersion(): NativeResult;
  countGeoData(datDir: string, name: string, geoType: string): NativeResult;
  readGeoFiles(configJson: string): NativeResult;
  getFreePorts(count: number): NativeResult;
  convertShareLinksToXrayJson(text: string): NativeResult;
  convertXrayJsonToShareLinks(configJson: string): NativeResult;
  // sing-box second core (optional). singboxProbe is UI-thread safe; the rest must
  // be called from the VPN native thread.
  singboxProbe(): NativeResult;
  singboxVersion(): NativeResult;
  singboxSetTunFd(tunFd: number): NativeResult;
  singboxStart(configJson: string, workDir: string): NativeResult;
  singboxStop(): NativeResult;
}

const bridge = heyNative as NativeBridge;

export function validateNativeConfig(configJson: string): NativeResult {
  return bridge.validateConfig(configJson);
}

export function setNativeTunFd(tunFd: number): NativeResult {
  return bridge.setTunFd(tunFd);
}

export function startNativeXray(configJson: string, workDir: string): NativeResult {
  return bridge.startXray(configJson, workDir);
}

export function stopNativeXray(): NativeResult {
  return bridge.stopXray();
}

export function getNativeStats(): RuntimeStats {
  return bridge.getStats();
}

export function startNativeTun2Socks(tunFd: number, socksHost: string, socksPort: number, mtu: number): NativeResult {
  return bridge.startTun2Socks(tunFd, socksHost, socksPort, mtu);
}

// hev-socks5-tunnel 数据面（「使用 Hev TUN 引擎」开关打开时走它，对照 gvisor 的
// startNativeTun2Socks）。configYaml 由 HevTunConfig.buildHevTunConfigYaml 生成。
// 停止仍走 stopNativeTun2Socks —— 原生侧按当前引擎自动分发。
export function startNativeHevTun(tunFd: number, configYaml: string): NativeResult {
  return bridge.startHevTun(tunFd, configYaml);
}

export function stopNativeTun2Socks(): NativeResult {
  return bridge.stopTun2Socks();
}

export function pingNativeOutbound(configJson: string, datDir: string, url: string, timeoutSeconds: number, proxy: string): NativePingResult {
  return bridge.pingOutbound(configJson, datDir, url, timeoutSeconds, proxy);
}

// Pre-connect config validation via the core. Returns a clean error message
// extracted from the CallResponse on failure. When the core symbol is missing
// the bridge reports ok=true (skipped) so startup is never blocked.
export function testNativeXrayConfig(configJson: string, workDir: string): NativeResult {
  const result = bridge.testXrayConfig(configJson, workDir);
  if (result.ok) {
    return { ok: true, message: 'Native config preflight passed.' };
  }
  return { ok: false, message: extractCallError(result.message) };
}

// Bundled Xray core version string, or ok=false when unavailable.
export function nativeXrayVersion(): NativeResult {
  const result = bridge.xrayVersion();
  if (!result.ok) {
    return { ok: false, message: result.message };
  }
  return { ok: true, message: extractCallData(result.message) };
}

// probeNativeSingbox 只 dlopen+dlsym（不调 Go），UI 线程点按安全：message 直接是
// 「loaded + 符号列表」或失败原因。用于关于页诊断。
export function probeNativeSingbox(): NativeResult {
  return bridge.singboxProbe();
}

// nativeSingboxVersion 真调 CGoSingBoxVersion —— 只应从 VPN 原生线程调用，
// UI 线程冷调可能 SIGSEGV（与 Xray 同墙）。
export function nativeSingboxVersion(): NativeResult {
  const result = bridge.singboxVersion();
  if (!result.ok) {
    return { ok: false, message: result.message };
  }
  return { ok: true, message: extractCallData(result.message) };
}

// sing-box 生命周期（与 Xray 平行）。必须从 VPN 原生线程调用。
// 顺序：先 setNativeSingboxTunFd 把 tun fd 存进核，再 startNativeSingbox。
export function setNativeSingboxTunFd(tunFd: number): NativeResult {
  return bridge.singboxSetTunFd(tunFd);
}

export function startNativeSingbox(configJson: string, workDir: string): NativeResult {
  return bridge.singboxStart(configJson, workDir);
}

export function stopNativeSingbox(): NativeResult {
  return bridge.singboxStop();
}

// Asks libXray to parse a geosite/geoip .dat file and write {name}.json into
// the same directory. `geoType` is "domain" for geosite and "ip" for geoip.
export function countNativeGeoData(datDir: string, name: string, geoType: string): NativeResult {
  const result = bridge.countGeoData(datDir, name, geoType);
  if (result.ok) {
    return { ok: true, message: 'Geo data counted.' };
  }
  return { ok: false, message: extractCallError(result.message) };
}

// Reads the geosite/geoip .dat file names referenced by an Xray config JSON.
export function readNativeGeoFiles(configJson: string): NativeGeoFilesResult {
  const result = bridge.readGeoFiles(configJson);
  if (!result.ok) {
    return { ok: false, domainFiles: [], ipFiles: [], message: extractCallError(result.message) };
  }

  try {
    const envelope = JSON.parse(result.message) as CallResponseAny;
    const data = normalizeGeoFilesData(envelope.data);
    return {
      ok: true,
      domainFiles: normalizeStringArray(data.domain),
      ipFiles: normalizeStringArray(data.ip),
      message: ''
    };
  } catch (error) {
    return { ok: false, domainFiles: [], ipFiles: [], message: `Geo files parse failed: ${JSON.stringify(error)}` };
  }
}

// Requests free localhost TCP ports from libXray. Older cores without
// CGoGetFreePorts simply return ok=false and callers should fall back.
export function getNativeFreePorts(count: number): NativeFreePortsResult {
  const result = bridge.getFreePorts(count);
  if (!result.ok) {
    return { ok: false, ports: [], message: extractCallError(result.message) };
  }

  try {
    const envelope = JSON.parse(result.message) as CallResponseAny;
    const data = normalizeFreePortsData(envelope.data);
    return { ok: true, ports: normalizePortArray(data.ports), message: '' };
  } catch (error) {
    return { ok: false, ports: [], message: `Free ports parse failed: ${JSON.stringify(error)}` };
  }
}

// Converts v2rayN plain/base64 text, Xray JSON, or Clash.Meta YAML through
// libXray and returns the full Xray config JSON from the CallResponse data.
export function convertNativeShareLinksToXrayJson(text: string): NativeXrayJsonResult {
  const result = bridge.convertShareLinksToXrayJson(text);
  if (!result.ok) {
    return { ok: false, configJson: '', message: extractCallError(result.message) };
  }

  try {
    const configJson = extractCallDataAsText(result.message);
    if (configJson.length === 0) {
      return { ok: false, configJson: '', message: 'Native share conversion returned empty config.' };
    }
    return { ok: true, configJson, message: '' };
  } catch (error) {
    return { ok: false, configJson: '', message: `Share conversion parse failed: ${JSON.stringify(error)}` };
  }
}

// Best-effort reverse conversion from a full Xray config to share links. Some
// outbound protocols are skipped by libXray when no share-link format exists.
export function convertNativeXrayJsonToShareLinks(configJson: string): NativeTextResult {
  const result = bridge.convertXrayJsonToShareLinks(configJson);
  if (!result.ok) {
    return { ok: false, text: '', message: extractCallError(result.message) };
  }

  try {
    const text = extractCallDataAsText(result.message);
    if (text.length === 0) {
      return { ok: false, text: '', message: 'Native share export returned empty text.' };
    }
    return { ok: true, text, message: '' };
  } catch (error) {
    return { ok: false, text: '', message: `Share export parse failed: ${JSON.stringify(error)}` };
  }
}

// Queries the running Xray metrics endpoint and sums real per-tag outbound
// traffic. `server` is the expvar URL, e.g. http://127.0.0.1:10845/debug/vars.
export function queryNativeTraffic(server: string): NativeTrafficStats {
  const result = bridge.queryStats(server);
  if (!result.ok) {
    return { ok: false, uploadBytes: 0, downloadBytes: 0, message: result.message };
  }
  return parseTrafficResponse(result.message);
}

function parseTrafficResponse(callResponseJson: string): NativeTrafficStats {
  try {
    const envelope = JSON.parse(callResponseJson) as CallResponseString;
    if (envelope.data === undefined || envelope.data.length === 0) {
      return { ok: false, uploadBytes: 0, downloadBytes: 0, message: 'Empty stats payload.' };
    }
    const expvar = JSON.parse(envelope.data) as ExpvarRoot;
    const outbound = expvar.stats?.outbound;
    if (outbound === undefined) {
      return { ok: true, uploadBytes: 0, downloadBytes: 0, message: '' };
    }

    let uploadBytes = 0;
    let downloadBytes = 0;
    const tags = Object.keys(outbound);
    for (let index = 0; index < tags.length; index++) {
      const tag = tags[index];
      // 'block' is a blackhole sink; its bytes are not real traffic.
      if (tag === 'block') {
        continue;
      }
      const counters = outbound[tag];
      const up = counters['uplink'];
      const down = counters['downlink'];
      if (typeof up === 'number') {
        uploadBytes += up;
      }
      if (typeof down === 'number') {
        downloadBytes += down;
      }
    }
    return { ok: true, uploadBytes, downloadBytes, message: '' };
  } catch (error) {
    return { ok: false, uploadBytes: 0, downloadBytes: 0, message: `Stats parse failed: ${JSON.stringify(error)}` };
  }
}

function normalizeGeoFilesData(value: Object | string | number | undefined): GeoFilesData {
  if (value === undefined) {
    return {};
  }
  if (typeof value === 'string') {
    if (value.length === 0) {
      return {};
    }
    return JSON.parse(value) as GeoFilesData;
  }
  if (typeof value === 'object') {
    return value as GeoFilesData;
  }
  return {};
}

function normalizeFreePortsData(value: Object | string | number | undefined): FreePortsData {
  if (value === undefined) {
    return {};
  }
  if (typeof value === 'string') {
    if (value.length === 0) {
      return {};
    }
    return JSON.parse(value) as FreePortsData;
  }
  if (typeof value === 'object') {
    return value as FreePortsData;
  }
  return {};
}

function normalizeStringArray(value: Array<string> | undefined): Array<string> {
  if (value === undefined) {
    return [];
  }
  const result = new Array<string>();
  value.forEach(item => {
    if (typeof item === 'string' && item.length > 0) {
      result.push(item);
    }
  });
  return result;
}

function normalizePortArray(value: Array<number> | undefined): Array<number> {
  if (value === undefined) {
    return [];
  }
  const result = new Array<number>();
  value.forEach(item => {
    if (typeof item === 'number' && item >= 1 && item <= 65535 && Math.floor(item) === item) {
      result.push(item);
    }
  });
  return result;
}

function extractCallError(message: string): string {
  try {
    const envelope = JSON.parse(message) as CallResponseString;
    if (envelope.err !== undefined && envelope.err.length > 0) {
      return envelope.err;
    }
  } catch (error) {
    // Not a CallResponse envelope (structural error or skipped message).
  }
  return message;
}

function extractCallData(message: string): string {
  try {
    const envelope = JSON.parse(message) as CallResponseString;
    if (envelope.data !== undefined && envelope.data.length > 0) {
      return envelope.data;
    }
  } catch (error) {
    // Not a CallResponse envelope; fall back to the raw message.
  }
  return message;
}

function extractCallDataAsText(message: string): string {
  const envelope = JSON.parse(message) as CallResponseAny;
  const data = envelope.data;
  if (data === undefined) {
    return '';
  }
  if (typeof data === 'string') {
    return data;
  }
  if (typeof data === 'number') {
    return data.toString();
  }
  return JSON.stringify(data, null, 2);
}
