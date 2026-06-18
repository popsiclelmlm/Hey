import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import Want from '@ohos.app.ability.Want';
import { RuntimeStats } from '../core/Profile';
import {
  createDefaultVpnConfig,
  normalizeVpnDnsAddresses,
  normalizeVpnMtu,
  VPN_COMMAND_KEY,
  VPN_COMMAND_STOP
} from './VpnConstants';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import {
  getNativeStats,
  queryNativeTraffic,
  setNativeTunFd,
  startNativeXray,
  stopNativeXray,
  testNativeXrayConfig
} from '../native/HeyNative';
import { METRICS_SERVER_URL } from '../core/XrayConfig';
import { DiagnosticLog } from '../services/DiagnosticLog';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'HeyVpnAbility';
const STATS_INTERVAL_MS: number = 2000;

export default class HeyVpnAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;
  private statsTimerId: number = -1;
  private sessionId: string = '';
  private cleaningUp: boolean = false;

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

    try {
      this.emitInfo('VPN start requested.', `configBytes=${configJson.length}`);
      // Non-blocking preflight: surface config issues early in diagnostics, but
      // never abort start on a not-ok result. CGoTestXray builds the core from
      // the full config (including the `tun` inbound) before the TUN fd is set,
      // so a false-positive here must not block the verified connection path —
      // startNativeXray below remains the source of truth for real failures.
      const validation = testNativeXrayConfig(configJson, this.context.filesDir);
      if (validation.ok) {
        this.emitInfo('Native config preflight passed.', validation.message);
      } else {
        this.emitInfo('Native config preflight warning.', validation.message);
      }

      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      this.emitInfo('Creating VPN connection.');
      const settings = await SETTINGS_CONTROLLER.load(this.context);
      const perAppEnabled = settings.perAppProxyEnabled;
      const bypassMode = settings.perAppProxyBypass ?? true;
      const appList = settings.perAppProxyList ?? [];
      const dnsAddresses = normalizeVpnDnsAddresses(settings.vpnDns);
      const vpnMtu = normalizeVpnMtu(settings.vpnMtu);
      const vpnConfig = createDefaultVpnConfig(perAppEnabled, bypassMode, appList, settings.vpnDns, settings.preferIpv6, vpnMtu);
      this.tunFd = await this.vpnConnection.create(vpnConfig);
      this.emitInfo('VPN created.', `tunFd=${this.tunFd}, dns=${dnsAddresses.join(',')}, ipv6=${settings.preferIpv6}, mtu=${vpnMtu}`);

      const tunResult = setNativeTunFd(this.tunFd);
      if (!tunResult.ok) {
        throw new Error(tunResult.message);
      }
      this.emitInfo('Xray TUN fd configured.', tunResult.message);

      const xrayResult = startNativeXray(configJson, this.context.filesDir);
      if (!xrayResult.ok) {
        throw new Error(xrayResult.message);
      }
      this.emitInfo('Xray started.', xrayResult.message);

      this.startStatsTimer();
      this.emitInfo('Native VPN bridge started.', `session=${this.sessionId}`);
    } catch (error) {
      this.emitError('VPN start failed.', this.errorMessage(error));
      await this.cleanup();
    }
  }

  private getStringParameter(want: Want, key: string, fallback: string): string {
    const value = want.parameters?.[key];
    if (value === undefined || value === null) {
      return fallback;
    }
    return value.toString();
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
    this.stopStatsTimer();
    this.emitInfo('VPN cleanup started.', `tunFd=${this.tunFd}`);

    const xrayResult = stopNativeXray();
    this.emitInfo('Xray stop requested.', xrayResult.message);

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
