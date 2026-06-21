import { http, socket } from '@kit.NetworkKit';
import { taskpool } from '@kit.ArkTS';
import { XrayConfigType } from '../core/Profile';
import { DEFAULT_SOCKS_HOST, DELAY_TEST_SOCKS_PORT, buildDelayTestConfig } from '../core/XrayConfig';
import { NativePingResult, pingNativeOutbound } from '../native/HeyNative';

export interface DelayTestResult {
  ok: boolean;
  delayMs: number;
  status: string;
}

function isCoreUnavailable(message: string): boolean {
  const lower = message.toLowerCase();
  return lower.indexOf('unavailable') >= 0 || lower.indexOf('failed to load') >= 0 || lower.indexOf('symbol missing') >= 0;
}

// 在 TaskPool worker 线程上执行 native 延迟测试。pingNativeOutbound 是同步 cgo
// （建临时 Xray + ping），放到 worker 跑避免阻塞 UI 线程。cgo 在 worker 线程上由
// OHOS Go fork 的 TLSDESC 保证安全。必须是顶层 @Concurrent 函数（无闭包捕获）。
// socksPort 由调用方分配：并发测速时每个"槽"用固定且互不相同的端口，槽内顺序处理，
// 因此并发的 ping 不会撞端口，也无需 getNativeFreePorts（旧 .so 未导出该符号）。
@Concurrent
function runNativeDelayTest(outboundJson: string, datDir: string, url: string, timeoutSeconds: number, configType: string, socksPort: number): NativePingResult {
  const effectiveType: XrayConfigType | undefined = configType.length > 0 ? (configType as XrayConfigType) : undefined;
  let configJson = '';
  try {
    configJson = buildDelayTestConfig(outboundJson, socksPort, effectiveType).configJson;
  } catch (error) {
    return { ok: false, delayMs: -1, message: 'invalid-config' };
  }
  const proxy = `socks5://${DEFAULT_SOCKS_HOST}:${socksPort}`;
  return pingNativeOutbound(configJson, datDir, url, timeoutSeconds, proxy);
}

export class DelayTester {
  static async measureTcp(address: string, port: number, timeoutMs: number = 8000): Promise<DelayTestResult> {
    const target = address.trim();
    if (target.length === 0 || port <= 0 || port > 65535) {
      return {
        ok: false,
        delayMs: -1,
        status: 'invalid-endpoint'
      };
    }

    const startedAt = Date.now();
    const tcp = socket.constructTCPSocketInstance();
    try {
      await tcp.connect({
        address: {
          address: target,
          port
        },
        timeout: timeoutMs
      });
      return {
        ok: true,
        delayMs: Math.max(0, Date.now() - startedAt),
        status: 'tcp'
      };
    } catch (error) {
      return {
        ok: false,
        delayMs: -1,
        status: JSON.stringify(error)
      };
    } finally {
      try {
        await tcp.close();
      } catch (_) {
      }
    }
  }

  // socksPort：本次测速用的本地 socks 端口。并发测速时由调用方给每个并发槽分配一个
  // 固定且互不相同的端口（见 Index 的流式测速池），避免并发 ping 撞端口/撞配置文件。
  // 单点测速不传则用默认端口。
  static async measureNodeOutbound(outboundJson: string, datDir: string, url: string, timeoutMs: number = 8000, configType?: XrayConfigType, socksPort: number = DELAY_TEST_SOCKS_PORT): Promise<DelayTestResult> {
    const timeoutSeconds = Math.max(1, Math.floor(timeoutMs / 1000));
    let result: NativePingResult;
    try {
      // native cgo（建临时 Xray + ping）放到 TaskPool worker 线程跑，避免阻塞 UI。
      result = await taskpool.execute(
        runNativeDelayTest, outboundJson, datDir, url, timeoutSeconds, configType ?? '', socksPort
      ) as NativePingResult;
    } catch (error) {
      return {
        ok: false,
        delayMs: -1,
        status: JSON.stringify(error)
      };
    }

    if (result.ok && result.delayMs >= 0) {
      return {
        ok: true,
        delayMs: result.delayMs,
        status: 'ok'
      };
    }
    if (result.message === 'invalid-config') {
      return {
        ok: false,
        delayMs: -1,
        status: 'invalid-config'
      };
    }
    if (isCoreUnavailable(result.message)) {
      const fallback = await DelayTester.measure(url, timeoutMs);
      return {
        ok: fallback.ok,
        delayMs: fallback.delayMs,
        status: fallback.ok ? 'direct' : fallback.status
      };
    }
    return {
      ok: false,
      delayMs: -1,
      status: result.message.length > 0 ? result.message : 'ping-failed'
    };
  }


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
