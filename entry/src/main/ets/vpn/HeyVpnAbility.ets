import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import Want from '@ohos.app.ability.Want';
import { DEFAULT_SOCKS_PORT } from '../core/XrayConfig';
import { RuntimeStats } from '../core/Profile';
import {
  createDefaultVpnConfig,
  VPN_MTU
} from './VpnConstants';
import {
  getNativeStats,
  startNativeTun2Socks,
  startNativeXray,
  stopNativeTun2Socks,
  stopNativeXray,
  validateNativeConfig
} from '../native/HeyNative';
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
    this.startVpn(want);
  }

  onDestroy(): void {
    this.emitInfo('VPN ability destroying.', `session=${this.sessionId}`);
    this.cleanup();
  }

  private async startVpn(want: Want): Promise<void> {
    const configJson = this.getStringParameter(want, 'xrayConfigJson', '');
    const socksHost = this.getStringParameter(want, 'socksHost', '127.0.0.1');
    const socksPort = this.getNumberParameter(want, 'socksPort', DEFAULT_SOCKS_PORT);

    try {
      this.emitInfo('VPN start requested.', `configBytes=${configJson.length}, socks=${socksHost}:${socksPort}, mtu=${VPN_MTU}`);
      const validation = validateNativeConfig(configJson);
      if (!validation.ok) {
        throw new Error(validation.message);
      }
      this.emitInfo('Native config validated.', validation.message);

      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      this.emitInfo('Creating VPN connection.');
      this.tunFd = await this.vpnConnection.create(createDefaultVpnConfig());
      this.emitInfo('VPN created.', `tunFd=${this.tunFd}`);

      const xrayResult = startNativeXray(configJson);
      if (!xrayResult.ok) {
        throw new Error(xrayResult.message);
      }
      this.emitInfo('Xray started.', xrayResult.message);

      const tunResult = startNativeTun2Socks(this.tunFd, socksHost, socksPort, VPN_MTU);
      if (!tunResult.ok) {
        throw new Error(tunResult.message);
      }
      this.emitInfo('tun2socks started.', tunResult.message);

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

  private getNumberParameter(want: Want, key: string, fallback: number): number {
    const value = want.parameters?.[key];
    if (value === undefined || value === null) {
      return fallback;
    }
    const parsed = Number(value.toString());
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return parsed;
  }

  private async cleanup(): Promise<void> {
    if (this.cleaningUp) {
      return;
    }
    this.cleaningUp = true;
    this.stopStatsTimer();
    this.emitInfo('VPN cleanup started.', `tunFd=${this.tunFd}`);

    const tunResult = stopNativeTun2Socks();
    this.emitInfo('tun2socks stop requested.', tunResult.message);

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
    DiagnosticLog.append(this.context, {
      at: Date.now(),
      level: 'info',
      source: 'vpn-stats',
      message: 'Native bridge stats.',
      details: stats.lastMessage,
      uploadBytes: stats.uploadBytes,
      downloadBytes: stats.downloadBytes,
      xrayRunning: stats.xrayRunning,
      tun2SocksRunning: stats.tun2SocksRunning
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
