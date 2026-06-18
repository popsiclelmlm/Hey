import { http } from '@kit.NetworkKit';
import { DEFAULT_IP_API_URL } from '../core/Profile';
import { LOCAL_HTTP_PROXY_HOST } from '../core/XrayConfig';

interface RemoteIpLocation {
  country_code?: string;
}

interface RemoteIpPayload {
  ip?: string;
  clientIp?: string;
  ip_addr?: string;
  query?: string;
  country_code?: string;
  country?: string;
  countryCode?: string;
  location?: RemoteIpLocation;
}

export interface RemoteIpInfoResult {
  ok: boolean;
  summary: string;
  status: string;
}

export async function fetchRemoteIpInfo(ipApiUrl: string, proxyPort: number, timeoutMs: number = 5000): Promise<RemoteIpInfoResult> {
  const target = normalizeIpApiUrl(ipApiUrl);
  if (target.length === 0) {
    return failedRemoteIpInfo('invalid-url');
  }
  if (!shouldUseHttpProxy(proxyPort)) {
    return failedRemoteIpInfo('proxy-unavailable');
  }

  const request = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: timeoutMs,
      connectTimeout: timeoutMs,
      usingCache: false,
      header: {
        'User-Agent': 'Hey/0.1 HarmonyOS NEXT Xray Client',
        'Accept': 'application/json, text/plain, */*',
        'Cache-Control': 'no-cache'
      },
      usingProxy: {
        host: LOCAL_HTTP_PROXY_HOST,
        port: proxyPort,
        exclusionList: []
      }
    };
    const response = await request.request(target, options);
    const responseCode = Number(response.responseCode);
    if (responseCode < 200 || responseCode >= 300) {
      return failedRemoteIpInfo(`HTTP ${response.responseCode}`);
    }
    return parseRemoteIpInfoContent(responseBodyText(response.result));
  } catch (error) {
    return failedRemoteIpInfo(JSON.stringify(error));
  } finally {
    request.destroy();
  }
}

export function parseRemoteIpInfoContent(content: string): RemoteIpInfoResult {
  try {
    const payload = JSON.parse(content) as RemoteIpPayload;
    const ip = firstNonEmpty([
      payload.ip,
      payload.clientIp,
      payload.ip_addr,
      payload.query
    ]);
    const country = firstNonEmpty([
      payload.country_code,
      payload.country,
      payload.countryCode,
      payload.location?.country_code
    ]);
    return {
      ok: true,
      summary: `(${country.length > 0 ? country : 'unknown'}) ${ip.length > 0 ? ip : 'unknown'}`,
      status: 'ok'
    };
  } catch (error) {
    return failedRemoteIpInfo(`parse-failed: ${JSON.stringify(error)}`);
  }
}

export function normalizeIpApiUrl(ipApiUrl: string): string {
  const target = ipApiUrl.trim().length > 0 ? ipApiUrl.trim() : DEFAULT_IP_API_URL;
  if (target.startsWith('http://') || target.startsWith('https://')) {
    return target;
  }
  return '';
}

function responseBodyText(result: Object | string | ArrayBuffer): string {
  if (typeof result === 'string') {
    return result;
  }
  const text = JSON.stringify(result);
  return text === undefined ? '' : text;
}

function shouldUseHttpProxy(proxyPort: number): boolean {
  return proxyPort > 0 && Math.floor(proxyPort) === proxyPort && proxyPort <= 65535;
}

function firstNonEmpty(values: Array<string | undefined>): string {
  for (let index = 0; index < values.length; index++) {
    const value = values[index];
    if (value !== undefined && value.trim().length > 0) {
      return value.trim();
    }
  }
  return '';
}

function failedRemoteIpInfo(status: string): RemoteIpInfoResult {
  return {
    ok: false,
    summary: '',
    status
  };
}
