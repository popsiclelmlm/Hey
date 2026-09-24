import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import Want from '@ohos.app.ability.Want';
import { NetworkProbe } from '../services/NetworkProbe';
import { NetAutomationConfig, NET_ACTION_DISCONNECT, decideNetAutomationAction } from '../core/NetworkAutomation';
import { NetSceneStopFlag } from '../services/NetSceneStopFlag';
import { resolveVpnInterfaceAddressConfig, RuntimeStats } from '../core/Profile';
import {
  createDefaultVpnConfig,
  normalizeVpnDnsAddresses,
  normalizeVpnMtu,
  VPN_COMMAND_KEY,
  VPN_COMMAND_STOP,
  VPN_DATA_PLANE_PASS_KEY,
  VPN_DATA_PLANE_USER_KEY
} from './VpnConstants';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import {
  getNativeStats,
  queryNativeTraffic,
  startNativeHevTun,
  startNativeSingbox,
  startNativeTun2Socks,
  startNativeXray,
  stopNativeSingbox,
  stopNativeTun2Socks,
  stopNativeXray
} from '../native/HeyNative';
import { METRICS_SERVER_URL, VPN_DATA_SOCKS_HOST, VPN_DATA_SOCKS_PORT } from '../core/XrayConfig';
import { buildHevTunConfigYaml } from '../core/HevTunConfig';
import { DataPlaneCredentials, tun2socksProxyHost } from '../core/DataPlaneAuth';
import { isSingboxCore } from '../core/CoreSelection';
import { DiagnosticLog } from '../services/DiagnosticLog';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'HeyVpnAbility';
const STATS_INTERVAL_MS: number = 2000;
// 网络场景轮询间隔：VPN 扩展进程后台存活，自驱动定时器可跑（区别于后台收不到的 connection.on 事件）。
const NET_SCENE_POLL_MS: number = 5000;

export default class HeyVpnAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;
  private statsTimerId: number = -1;
  private sessionId: string = '';
  private cleaningUp: boolean = false;
  // 网络场景自动化（后台断开）：VPN 扩展进程内轮询网络，切到可信网络即拆隧道。
  private netScenePollTimerId: number = -1;
  private netSceneSignature: string = '';
  private netSceneSeeded: boolean = false;

  onCreate(want: Want): void {
    this.sessionId = Date.now().toString();
    this.emitInfo('VPN ability created.', `session=${this.sessionId}`);
    if (this.isStopCommand(want)) {
      this.requestCleanup('VPN stop command received on create.', 'startId=0');
      return;
    }
    this.startVpn(want).catch((error: Object) => {
      this.emitError('VPN start task failed.', this.errorMessage(error));
    });
  }

  onRequest(want: Want, startId: number): void {
    if (this.isStopCommand(want)) {
      this.requestCleanup('VPN stop command received.', `startId=${startId}`);
      return;
    }
    this.emitInfo('VPN request ignored.', `startId=${startId}, session=${this.sessionId}`);
  }

  onDestroy(): void {
    this.emitInfo('VPN ability destroying.', `session=${this.sessionId}`);
    if (this.vpnConnection !== null || this.tunFd >= 0) {
      this.requestCleanup('VPN destroy cleanup requested.', `session=${this.sessionId}`);
    }
  }

  private async startVpn(want: Want): Promise<void> {
    const configJson = this.getStringParameter(want, 'xrayConfigJson', '');
    const useSingbox = isSingboxCore(this.getStringParameter(want, 'coreType', 'xray'));
    const dataPlaneCredentials = this.getDataPlaneCredentials(want);

    try {
      this.emitInfo('VPN start requested.', `core=${useSingbox ? 'singbox' : 'xray'}, configBytes=${configJson.length}`);
      // 不再做 testNativeXrayConfig 预检：重编后的 libXray 的 CGoTestXray 冷 cgo 入口
      // 会在 VPN 扩展进程里 SIGSEGV（真机 ALN-AL80 / HarmonyOS 6.1 复现，崩在本行附近，
      // Go-on-musl 的 TLS/栈问题），导致扩展进程当场死亡、无法回写启动状态。预检本就是
      // 非阻塞诊断，startNativeXray 才是真相来源，直接走它（与 1.1 行为一致）。

      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      this.emitInfo('Creating VPN connection.');
      const settings = await SETTINGS_CONTROLLER.load(this.context);
      const perAppEnabled = settings.perAppProxyEnabled;
      const bypassMode = settings.perAppProxyBypass ?? false;
      const appList = settings.perAppProxyList ?? [];
      const dnsAddresses = normalizeVpnDnsAddresses(settings.vpnDns);
      const vpnMtu = normalizeVpnMtu(settings.vpnMtu);
      const addressConfig = resolveVpnInterfaceAddressConfig(settings.vpnInterfaceAddressIndex);
      const vpnConfig = createDefaultVpnConfig(
        perAppEnabled,
        bypassMode,
        appList,
        settings.vpnDns,
        settings.ipv6Enabled,
        vpnMtu,
        settings.vpnInterfaceAddressIndex,
        settings.vpnBypassLan,
        settings.routingRules,
        settings.trafficMode === 'rules' && settings.routeOnlyEnabled
      );
      this.tunFd = await this.vpnConnection.create(vpnConfig);
      this.emitInfo('VPN created.', `tunFd=${this.tunFd}, dns=${dnsAddresses.join(',')}, ipv6=${settings.ipv6Enabled}, preferIpv6=${settings.preferIpv6}, mtu=${vpnMtu}, address=${addressConfig.displayName}, bypassLan=${settings.vpnBypassLan}`);

      // 两个内核统一走 tun2socks 数据面：内核在 127.0.0.1:VPN_DATA_SOCKS_PORT 起本地
      // SOCKS 入站，再把 Harmony TUN fd 的流量转发进去。sing-box 因此不需要把 tun fd
      // 交给核心（无 OpenTun / gvisor tun 栈），与 Xray 路径一致。
      const coreResult = useSingbox
        ? startNativeSingbox(configJson, this.context.filesDir)
        : startNativeXray(configJson, this.context.filesDir);
      if (!coreResult.ok) {
        throw new Error(coreResult.message);
      }
      this.emitInfo(`${useSingbox ? 'sing-box' : 'Xray'} started.`, coreResult.message);

      // 数据面引擎二选一：useHevTun=true 走 hev-socks5-tunnel（高性能，libhevsocks5tun.so），
      // 否则走默认 gvisor/xjasonlyu（libheytun2socks.so）。两者都把 TUN fd 转发到同一个
      // 本地 SOCKS 入站，只是实现不同。停止时统一调 stopNativeTun2Socks（原生侧按引擎分发）。
      // 数据面入站带会话凭据时（主进程生成、随 want 传入），两个引擎都以用户名密码认证。
      const useHevTun = settings.useHevTun;
      const tun2socksResult = useHevTun
        ? startNativeHevTun(
            this.tunFd,
            buildHevTunConfigYaml(vpnMtu, VPN_DATA_SOCKS_HOST, VPN_DATA_SOCKS_PORT, settings.hevTunLogLevel, settings.hevTunRwTimeout,
              dataPlaneCredentials)
          )
        : startNativeTun2Socks(this.tunFd, tun2socksProxyHost(VPN_DATA_SOCKS_HOST, dataPlaneCredentials), VPN_DATA_SOCKS_PORT, vpnMtu);
      if (!tun2socksResult.ok) {
        throw new Error(tun2socksResult.message);
      }
      this.emitInfo('tun data plane started.', `engine=${useHevTun ? 'hev' : 'gvisor'}, ${VPN_DATA_SOCKS_HOST}:${VPN_DATA_SOCKS_PORT}, auth=${dataPlaneCredentials !== undefined ? 'on' : 'off'}, mtu=${vpnMtu}, core=${useSingbox ? 'singbox' : 'xray'}, ${tun2socksResult.message}`);

      if (settings.speedEnabled) {
        this.startStatsTimer();
      } else {
        this.stopStatsTimer();
        this.emitInfo('Speed stats disabled by settings.');
      }
      this.emitInfo('Native VPN bridge started.', `session=${this.sessionId}`);
      this.startNetScenePoll();
    } catch (error) {
      this.emitError('VPN start failed.', this.errorMessage(error));
      await this.cleanup();
    }
  }

  // 在 VPN 扩展进程内用自驱动定时器轮询网络场景。VPN 隧道运行期该进程持续存活，
  // 定时器在后台/熄屏仍会触发（与 2s 统计定时器同理），弥补后台收不到 connection.on 事件的限制。
  private startNetScenePoll(): void {
    this.stopNetScenePoll();
    this.netSceneSeeded = false;
    this.netSceneSignature = '';
    this.netScenePollTimerId = setInterval(() => {
      this.pollNetScene();
    }, NET_SCENE_POLL_MS);
  }

  private stopNetScenePoll(): void {
    if (this.netScenePollTimerId >= 0) {
      clearInterval(this.netScenePollTimerId);
      this.netScenePollTimerId = -1;
    }
  }

  private async pollNetScene(): Promise<void> {
    if (this.cleaningUp) {
      return;
    }
    try {
      const settings = await SETTINGS_CONTROLLER.load(this.context);
      if (!settings.netAutomationEnabled) {
        return;
      }
      const ctx = await NetworkProbe.readCurrentNetContext();
      const signature = `${ctx.kind}|${ctx.ssid ?? ''}`;
      const cfg: NetAutomationConfig = {
        enabled: settings.netAutomationEnabled,
        // 固定为「仅可信网络自动断开」——不做自动连接（已移除方向选项）。
        trustedSsids: settings.netAutomationTrustedSsids,
        cellularTrusted: settings.netAutomationCellularTrusted
      };
      const action = decideNetAutomationAction(ctx, cfg, true);
      // 诊断：确认后台轮询是否在跑、SSID 是否可读、决策是否正确。
      this.emitInfo('Net scene poll.',
        `kind=${ctx.kind}; ssid=${ctx.ssid ?? '<none>'}; seeded=${this.netSceneSeeded}; sig=${signature}; action=${action}`);
      // 首次只 seed 不动作——避免拆掉用户「在可信网络手动开的 VPN」；仅对之后的网络切换生效。
      if (!this.netSceneSeeded) {
        this.netSceneSeeded = true;
        this.netSceneSignature = signature;
        return;
      }
      if (signature === this.netSceneSignature) {
        return;
      }
      this.netSceneSignature = signature;
      if (action === NET_ACTION_DISCONNECT) {
        this.emitInfo('Net scene: trusted network, auto-disconnecting.', `kind=${ctx.kind}`);
        // 写跨进程标志，供主进程回前台校正「运行中」滞留状态。
        await NetSceneStopFlag.markStopped(this.context, Date.now());
        this.requestCleanup('Network scene auto-disconnect.', `session=${this.sessionId}`);
      }
    } catch (error) {
      this.emitInfo('Net scene poll failed.', this.errorMessage(error));
    }
  }

  private getStringParameter(want: Want, key: string, fallback: string): string {
    const value = want.parameters?.[key];
    if (value === undefined || value === null) {
      return fallback;
    }
    return value.toString();
  }

  private getDataPlaneCredentials(want: Want): DataPlaneCredentials | undefined {
    const username = this.getStringParameter(want, VPN_DATA_PLANE_USER_KEY, '');
    const password = this.getStringParameter(want, VPN_DATA_PLANE_PASS_KEY, '');
    if (username.length === 0 || password.length === 0) {
      return undefined;
    }
    return { username, password };
  }

  private isStopCommand(want: Want): boolean {
    return this.getStringParameter(want, VPN_COMMAND_KEY, '') === VPN_COMMAND_STOP;
  }

  private requestCleanup(message: string, details: string): void {
    this.emitInfo(message, details);
    this.cleanup().catch((error: Object) => {
      this.emitError('VPN cleanup task failed.', this.errorMessage(error));
    });
  }

  private async cleanup(): Promise<void> {
    if (this.cleaningUp) {
      return;
    }
    this.cleaningUp = true;
    this.stopNetScenePoll();
    this.stopStatsTimer();
    this.emitInfo('VPN cleanup started.', `tunFd=${this.tunFd}`);

    // 先停 tun2socks 适配器（停止往 SOCKS 转发），再停内核。各操作幂等（未运行即 no-op），
    // 无论本会话用哪条数据面都安全。
    const tun2socksResult = stopNativeTun2Socks();
    this.emitInfo('tun2socks stop requested.', tun2socksResult.message);
    const xrayResult = stopNativeXray();
    this.emitInfo('Xray stop requested.', xrayResult.message);
    const singboxResult = stopNativeSingbox();
    this.emitInfo('sing-box stop requested.', singboxResult.message);

    if (this.vpnConnection !== null) {
      try {
        await this.vpnConnection.destroy();
        this.emitInfo('VPN destroyed.');
      } catch (error) {
        const businessError = error as BusinessError;
        this.emitError('VPN destroy failed.', businessError.message ?? JSON.stringify(error));
      }
    }

    this.vpnConnection = null;
    this.tunFd = -1;
    this.cleaningUp = false;
    this.emitInfo('VPN cleanup finished.', `session=${this.sessionId}`);
  }

  private startStatsTimer(): void {
    this.stopStatsTimer();
    this.statsTimerId = setInterval(() => {
      this.recordStats();
    }, STATS_INTERVAL_MS);
    this.recordStats();
  }

  private stopStatsTimer(): void {
    if (this.statsTimerId >= 0) {
      clearInterval(this.statsTimerId);
      this.statsTimerId = -1;
    }
  }

  private recordStats(): void {
    const stats: RuntimeStats = getNativeStats();
    // Prefer real per-tag counters from the Xray metrics endpoint; fall back to
    // the native bridge's own values when the metrics query is unavailable.
    let uploadBytes = stats.uploadBytes;
    let downloadBytes = stats.downloadBytes;
    const traffic = queryNativeTraffic(METRICS_SERVER_URL);
    if (traffic.ok) {
      uploadBytes = traffic.uploadBytes;
      downloadBytes = traffic.downloadBytes;
    }
    DiagnosticLog.append(this.context, {
      at: Date.now(),
      level: 'info',
      source: 'vpn-stats',
      message: 'Native bridge stats.',
      details: stats.lastMessage,
      uploadBytes,
      downloadBytes,
      xrayRunning: stats.xrayRunning,
      tunRunning: stats.tunRunning
    });
  }

  private emitInfo(message: string, details: string = ''): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s %{public}s', message, details);
    DiagnosticLog.append(this.context, {
      at: Date.now(),
      level: 'info',
      source: 'vpn',
      message,
      details
    });
  }

  private emitError(message: string, details: string = ''): void {
    hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s %{public}s', message, details);
    DiagnosticLog.append(this.context, {
      at: Date.now(),
      level: 'error',
      source: 'vpn',
      message,
      details
    });
  }

  private errorMessage(error: Object): string {
    const businessError = error as BusinessError;
    return businessError.message ?? JSON.stringify(error);
  }
}
