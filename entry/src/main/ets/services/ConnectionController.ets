import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSettings, ConnectionStatus, GeneratedXrayConfig, ProxyProfile, RuntimeStats } from '../core/Profile';
import { buildXrayConfig, buildXrayConfigWithSettings, validateOutboundJson } from '../core/XrayConfig';
import { createStopVpnWant, createVpnWant } from '../vpn/VpnConstants';
import { getNativeStats } from '../native/HeyNative';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'HeyVpn';
const START_VPN_TIMEOUT_MS: number = 10000;

export interface ConnectionSnapshot {
  status: ConnectionStatus;
  startedAt: number;
  lastError: string;
  generatedConfig: GeneratedXrayConfig | null;
}

export class ConnectionController {
  private status: ConnectionStatus = ConnectionStatus.IDLE;
  private startedAt: number = 0;
  private lastError: string = '';
  private generatedConfig: GeneratedXrayConfig | null = null;

  getSnapshot(): ConnectionSnapshot {
    return {
      status: this.status,
      startedAt: this.startedAt,
      lastError: this.lastError,
      generatedConfig: this.generatedConfig
    };
  }

  getStats(): RuntimeStats {
    const stats = getNativeStats();
    if (this.status === ConnectionStatus.RUNNING) {
      return {
        uploadBytes: stats.uploadBytes,
        downloadBytes: stats.downloadBytes,
        xrayRunning: true,
        tun2SocksRunning: true,
        lastMessage: 'VPN extension owns the native bridge. Wire IPC stats after real libXray/tun2socks integration.'
      };
    }
    return stats;
  }

  async start(profile: ProxyProfile, settings?: AppSettings): Promise<ConnectionSnapshot> {
    if (this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.RUNNING) {
      return this.getSnapshot();
    }

    const validation = validateOutboundJson(profile.outboundJson);
    if (!validation.valid) {
      this.status = ConnectionStatus.ERROR;
      this.lastError = validation.message;
      return this.getSnapshot();
    }

    this.status = ConnectionStatus.STARTING;
    this.lastError = '';
    this.generatedConfig = settings === undefined ? buildXrayConfig(profile.outboundJson) : buildXrayConfigWithSettings(profile.outboundJson, settings);

    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Calling startVpnExtensionAbility, configBytes=%{public}d, socks=%{public}s:%{public}d',
        this.generatedConfig.configJson.length,
        this.generatedConfig.socksHost,
        this.generatedConfig.socksPort);
      await this.withTimeout(vpnExtension.startVpnExtensionAbility(createVpnWant(
        this.generatedConfig.configJson,
        this.generatedConfig.socksHost,
        this.generatedConfig.socksPort
      )), START_VPN_TIMEOUT_MS, '启动 VPN 超时：系统 VPN 授权服务没有响应。若 hilog 中出现 com.huawei.hmos.vpndialog bundle not exist，说明当前系统镜像缺少 VPN 授权组件，请改用真机测试。');
      hilog.info(LOG_DOMAIN, LOG_TAG, 'startVpnExtensionAbility returned.');
      this.status = ConnectionStatus.RUNNING;
      this.startedAt = Date.now();
    } catch (error) {
      const businessError = error as BusinessError;
      this.status = ConnectionStatus.ERROR;
      this.lastError = `启动 VPN 失败：${businessError.message ?? JSON.stringify(error)}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'startVpnExtensionAbility failed: %{public}s', this.lastError);
    }
    return this.getSnapshot();
  }

  async stop(): Promise<ConnectionSnapshot> {
    if (this.status === ConnectionStatus.IDLE || this.status === ConnectionStatus.STOPPING) {
      return this.getSnapshot();
    }

    this.status = ConnectionStatus.STOPPING;
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Calling stopVpnExtensionAbility.');
      await vpnExtension.stopVpnExtensionAbility(createStopVpnWant());
      this.status = ConnectionStatus.IDLE;
      this.startedAt = 0;
      this.lastError = '';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'stopVpnExtensionAbility returned.');
    } catch (error) {
      const businessError = error as BusinessError;
      this.status = ConnectionStatus.ERROR;
      this.lastError = `停止 VPN 失败：${businessError.message ?? JSON.stringify(error)}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'stopVpnExtensionAbility failed: %{public}s', this.lastError);
    }
    return this.getSnapshot();
  }

  private withTimeout<T>(operation: Promise<T>, timeoutMs: number, message: string): Promise<T> {
    return new Promise<T>((resolve: (value: T | PromiseLike<T>) => void, reject: (reason?: Object) => void) => {
      const timerId = setTimeout(() => {
        reject(new Error(message));
      }, timeoutMs);

      operation.then((value: T) => {
        clearTimeout(timerId);
        resolve(value);
      }).catch((error: BusinessError) => {
        clearTimeout(timerId);
        reject(error);
      });
    });
  }
}
