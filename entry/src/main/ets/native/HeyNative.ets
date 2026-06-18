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

interface NativeBridge {
  validateConfig(configJson: string): NativeResult;
  setTunFd(tunFd: number): NativeResult;
  startXray(configJson: string, workDir: string): NativeResult;
  stopXray(): NativeResult;
  getStats(): RuntimeStats;
  pingOutbound(configJson: string, datDir: string, url: string, timeoutSeconds: number, proxy: string): NativePingResult;
  queryStats(server: string): NativeResult;
  testXrayConfig(configJson: string, workDir: string): NativeResult;
  xrayVersion(): NativeResult;
  countGeoData(datDir: string, name: string, geoType: string): NativeResult;
  readGeoFiles(configJson: string): NativeResult;
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
