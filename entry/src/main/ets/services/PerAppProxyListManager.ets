import { http } from '@kit.NetworkKit';
import {
  ANDROID_PACKAGE_NAME_LIST_URL,
  resolveAutoProxyPackageListContent
} from '../core/PerAppProxy';
import { LOCAL_HTTP_PROXY_HOST } from '../core/XrayConfig';

export type PerAppProxyListSource = 'remote' | 'fallback';

export interface PerAppProxyListResult {
  content: string;
  source: PerAppProxyListSource;
  error: string;
}

export class PerAppProxyListManager {
  async loadProxyPackageList(proxyPort: number = 0, timeoutMs: number = 5000): Promise<PerAppProxyListResult> {
    let lastError = '';
    try {
      const content = await this.fetchText(ANDROID_PACKAGE_NAME_LIST_URL, 0, timeoutMs);
      if (content.trim().length > 0) {
        return {
          content,
          source: 'remote',
          error: ''
        };
      }
      lastError = 'empty-remote-content';
    } catch (error) {
      lastError = JSON.stringify(error);
    }

    if (this.shouldUseHttpProxy(proxyPort)) {
      try {
        const content = await this.fetchText(ANDROID_PACKAGE_NAME_LIST_URL, proxyPort, timeoutMs);
        if (content.trim().length > 0) {
          return {
            content,
            source: 'remote',
            error: ''
          };
        }
        lastError = 'empty-proxy-content';
      } catch (error) {
        lastError = JSON.stringify(error);
      }
    }

    return {
      content: resolveAutoProxyPackageListContent(undefined),
      source: 'fallback',
      error: lastError
    };
  }

  private async fetchText(url: string, proxyPort: number, timeoutMs: number): Promise<string> {
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
          'Accept': 'text/plain, */*',
          'Cache-Control': 'no-cache'
        }
      };
      if (this.shouldUseHttpProxy(proxyPort)) {
        options.usingProxy = {
          host: LOCAL_HTTP_PROXY_HOST,
          port: proxyPort,
          exclusionList: []
        };
      }
      const response = await request.request(url, options);
      const responseCode = Number(response.responseCode);
      if (responseCode < 200 || responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      if (typeof response.result === 'string') {
        return response.result;
      }
      const text = JSON.stringify(response.result);
      return text === undefined ? '' : text;
    } finally {
      request.destroy();
    }
  }

  private shouldUseHttpProxy(proxyPort: number): boolean {
    return proxyPort > 0 && Math.floor(proxyPort) === proxyPort && proxyPort <= 65535;
  }
}

export const PER_APP_PROXY_LIST_MANAGER: PerAppProxyListManager = new PerAppProxyListManager();
