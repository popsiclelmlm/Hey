import { http } from '@kit.NetworkKit';

export interface DelayTestResult {
  ok: boolean;
  delayMs: number;
  status: string;
}

export class DelayTester {
  static async measure(url: string, timeoutMs: number = 8000): Promise<DelayTestResult> {
    const target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      return {
        ok: false,
        delayMs: -1,
        status: 'invalid-url'
      };
    }

    const startedAt = Date.now();
    const request = http.createHttp();
    try {
      const response = await request.request(target, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: timeoutMs,
        connectTimeout: timeoutMs,
        header: {
          'User-Agent': 'Hey/0.1 HarmonyOS NEXT Xray Client',
          'Accept': '*/*',
          'Cache-Control': 'no-cache'
        }
      });
      const delayMs = Math.max(0, Date.now() - startedAt);
      const responseCode = Number(response.responseCode);
      return {
        ok: responseCode >= 200 && responseCode < 500,
        delayMs,
        status: `HTTP ${responseCode}`
      };
    } catch (error) {
      return {
        ok: false,
        delayMs: -1,
        status: JSON.stringify(error)
      };
    } finally {
      request.destroy();
    }
  }
}
