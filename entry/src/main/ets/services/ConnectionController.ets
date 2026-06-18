import { common } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { APP_MODE_PROXY_ONLY, APP_MODE_VPN, AppRuntimeMode, AppSettings, ConnectionStatus, GeneratedXrayConfig, normalizeAppRuntimeMode, ProxyProfile, RuntimeStats } from '../core/Profile';
import { resolveDynamicPolicyGroupConfigJson } from '../core/AdvancedOutboundBuilder';
import { selectRuntimeLocalSocksPort, shouldUseDynamicLocalSocksPort, withRuntimeLocalSocksPort } from '../core/LocalProxy';
import { buildRuntimeXrayConfig, LOCAL_HTTP_PROXY_PORT, METRICS_PORT, normalizeConfigInput } from '../core/XrayConfig';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { createStopCommandVpnWant, createStopVpnWant, createVpnWant } from '../vpn/VpnConstants';
import { getNativeFreePorts, getNativeStats, startNativeXray, stopNativeXray, testNativeXrayConfig } from '../native/HeyNative';
import { DiagnosticEvent, DiagnosticLog } from './DiagnosticLog';
import { OUTBOUND_DOMAIN_RESOLVER } from './OutboundDomainResolver';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'HeyVpn';
const START_VPN_TIMEOUT_MS: number = 10000;
const START_VPN_READY_TIMEOUT_MS: number = 12000;
const STOP_VPN_CLEANUP_TIMEOUT_MS: number = 15000;
const DIAGNOSTIC_POLL_INTERVAL_MS: number = 250;
const VPN_STARTED_MESSAGE: string = 'Native VPN bridge started.';
const VPN_START_FAILED_MESSAGE: string = 'VPN start failed.';
const VPN_CLEANUP_FINISHED_MESSAGE: string = 'VPN cleanup finished.';

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
  private runtimeMode: AppRuntimeMode = APP_MODE_VPN;

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
      if (this.runtimeMode === APP_MODE_PROXY_ONLY) {
        return {
          uploadBytes: stats.uploadBytes,
          downloadBytes: stats.downloadBytes,
          xrayRunning: true,
          tunRunning: false,
          lastMessage: stats.lastMessage.length > 0 ? stats.lastMessage : 'Xray is running in proxy-only mode.'
        };
      }
      return {
        uploadBytes: stats.uploadBytes,
        downloadBytes: stats.downloadBytes,
        xrayRunning: true,
        tunRunning: true,
        lastMessage: 'VPN extension owns the native bridge. Xray is handling the TUN inbound directly.'
      };
    }
    return stats;
  }

  async start(context: common.Context, profile: ProxyProfile, settings?: AppSettings): Promise<ConnectionSnapshot> {
    if (this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.RUNNING) {
      return this.getSnapshot();
    }

    const validation = normalizeConfigInput(profile.outboundJson, profile.configType);
    if (!validation.valid) {
      this.status = ConnectionStatus.ERROR;
      this.lastError = validation.message;
      return this.getSnapshot();
    }

    this.status = ConnectionStatus.STARTING;
    this.lastError = '';
    const runtimeSettings = validation.configType === 'full' ? settings : this.resolveRuntimeSettings(settings);
    const runtimeConfigJson = await this.resolveRuntimeConfigJson(context, validation.normalizedJson, validation.configType);
    const resolvedRuntimeSettings = await OUTBOUND_DOMAIN_RESOLVER.resolve(context, runtimeConfigJson, runtimeSettings, validation.configType);
    this.generatedConfig = buildRuntimeXrayConfig(runtimeConfigJson, resolvedRuntimeSettings, validation.configType);
    this.runtimeMode = normalizeAppRuntimeMode(resolvedRuntimeSettings?.mode ?? settings?.mode, APP_MODE_VPN);
    const requestedAt = Date.now();

    try {
      if (this.runtimeMode === APP_MODE_PROXY_ONLY) {
        this.startProxyOnly(context);
        this.status = ConnectionStatus.RUNNING;
        this.startedAt = Date.now();
        return this.getSnapshot();
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Calling startVpnExtensionAbility, configBytes=%{public}d',
        this.generatedConfig.configJson.length);
      await this.withTimeout(vpnExtension.startVpnExtensionAbility(createVpnWant(
        this.generatedConfig.configJson
      )), START_VPN_TIMEOUT_MS, '启动 VPN 超时：系统 VPN 授权服务没有响应。若 hilog 中出现 com.huawei.hmos.vpndialog bundle not exist，说明当前系统镜像缺少 VPN 授权组件，请改用真机测试。');
      hilog.info(LOG_DOMAIN, LOG_TAG, 'startVpnExtensionAbility returned.');
      const startEvent = await this.waitForDiagnosticEvent(context, requestedAt, START_VPN_READY_TIMEOUT_MS, (event: DiagnosticEvent) => {
        return event.source === 'vpn' && (event.message === VPN_STARTED_MESSAGE || event.message === VPN_START_FAILED_MESSAGE);
      });
      if (startEvent === null) {
        throw new Error('启动 VPN 未确认完成：VPN 扩展没有回写启动完成状态。');
      }
      if (startEvent.message === VPN_START_FAILED_MESSAGE) {
        throw new Error(this.formatDiagnosticEvent(startEvent));
      }
      this.status = ConnectionStatus.RUNNING;
      this.startedAt = Date.now();
    } catch (error) {
      const businessError = error as BusinessError;
      this.status = ConnectionStatus.ERROR;
      const action = this.runtimeMode === APP_MODE_PROXY_ONLY ? '启动仅代理模式失败' : '启动 VPN 失败';
      this.lastError = `${action}：${businessError.message ?? JSON.stringify(error)}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'connection start failed: %{public}s', this.lastError);
    }
    return this.getSnapshot();
  }

  private startProxyOnly(context: common.Context): void {
    if (this.generatedConfig === null) {
      throw new Error('仅代理模式缺少运行配置。');
    }
    DiagnosticLog.append(context, {
      at: Date.now(),
      level: 'info',
      source: 'proxy',
      message: 'Proxy-only start requested.',
      details: `configBytes=${this.generatedConfig.configJson.length}`
    });
    const validation = testNativeXrayConfig(this.generatedConfig.configJson, context.filesDir);
    if (!validation.ok) {
      throw new Error(validation.message);
    }
    DiagnosticLog.append(context, {
      at: Date.now(),
      level: 'info',
      source: 'proxy',
      message: 'Native config preflight passed.',
      details: validation.message
    });
    const xrayResult = startNativeXray(this.generatedConfig.configJson, context.filesDir);
    if (!xrayResult.ok) {
      throw new Error(xrayResult.message);
    }
    DiagnosticLog.append(context, {
      at: Date.now(),
      level: 'info',
      source: 'proxy',
      message: 'Proxy-only mode started.',
      details: xrayResult.message
    });
  }

  private resolveRuntimeSettings(settings?: AppSettings): AppSettings | undefined {
    if (!shouldUseDynamicLocalSocksPort(settings)) {
      return settings;
    }
    const resolvedSettings = settings as AppSettings;
    const reservedPorts = this.reservedRuntimePorts(resolvedSettings);
    const freePorts = getNativeFreePorts(reservedPorts.length + 1);
    const runtimePort = selectRuntimeLocalSocksPort(resolvedSettings, freePorts.ok ? freePorts.ports : [], reservedPorts);
    return withRuntimeLocalSocksPort(resolvedSettings, runtimePort);
  }

  private async resolveRuntimeConfigJson(context: common.Context, configJson: string, configType?: string): Promise<string> {
    if (configType !== 'policy-group') {
      return configJson;
    }
    const subscription = await SubscriptionStore.load(context);
    return resolveDynamicPolicyGroupConfigJson(configJson, subscription.groups);
  }

  private reservedRuntimePorts(settings: AppSettings): Array<number> {
    const ports: Array<number> = [METRICS_PORT];
    if (settings.appendHttpProxy) {
      ports.push(LOCAL_HTTP_PROXY_PORT);
    }
    return ports;
  }

  async stop(context: common.Context): Promise<ConnectionSnapshot> {
    if (this.status === ConnectionStatus.IDLE || this.status === ConnectionStatus.STOPPING) {
      return this.getSnapshot();
    }

    this.status = ConnectionStatus.STOPPING;
    const requestedAt = Date.now();
    try {
      if (this.runtimeMode === APP_MODE_PROXY_ONLY) {
        this.stopProxyOnly(context);
        this.status = ConnectionStatus.IDLE;
        this.startedAt = 0;
        this.lastError = '';
        this.runtimeMode = APP_MODE_VPN;
        return this.getSnapshot();
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Calling startVpnExtensionAbility with stop command.');
      await this.withTimeout(vpnExtension.startVpnExtensionAbility(createStopCommandVpnWant()),
        START_VPN_TIMEOUT_MS,
        '停止 VPN 超时：VPN 扩展没有响应停止命令。');
      const cleanupEvent = await this.waitForDiagnosticEvent(context, requestedAt, STOP_VPN_CLEANUP_TIMEOUT_MS, (event: DiagnosticEvent) => {
        return event.source === 'vpn' && event.message === VPN_CLEANUP_FINISHED_MESSAGE;
      });
      if (cleanupEvent === null) {
        throw new Error('停止 VPN 未确认完成：VPN 扩展尚未回写清理完成状态。');
      }
      await vpnExtension.stopVpnExtensionAbility(createStopVpnWant());
      this.status = ConnectionStatus.IDLE;
      this.startedAt = 0;
      this.lastError = '';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'VPN stop command completed.');
    } catch (error) {
      const businessError = error as BusinessError;
      this.status = ConnectionStatus.ERROR;
      const action = this.runtimeMode === APP_MODE_PROXY_ONLY ? '停止仅代理模式失败' : '停止 VPN 失败';
      this.lastError = `${action}：${businessError.message ?? JSON.stringify(error)}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'connection stop failed: %{public}s', this.lastError);
    }
    return this.getSnapshot();
  }

  private stopProxyOnly(context: common.Context): void {
    DiagnosticLog.append(context, {
      at: Date.now(),
      level: 'info',
      source: 'proxy',
      message: 'Proxy-only stop requested.'
    });
    const xrayResult = stopNativeXray();
    if (!xrayResult.ok) {
      throw new Error(xrayResult.message);
    }
    DiagnosticLog.append(context, {
      at: Date.now(),
      level: 'info',
      source: 'proxy',
      message: 'Proxy-only mode stopped.',
      details: xrayResult.message
    });
  }

  private async waitForDiagnosticEvent(
    context: common.Context,
    since: number,
    timeoutMs: number,
    predicate: (event: DiagnosticEvent) => boolean
  ): Promise<DiagnosticEvent | null> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() <= deadline) {
      const event = await this.findDiagnosticEvent(context, since, predicate);
      if (event !== null) {
        return event;
      }
      await this.sleep(DIAGNOSTIC_POLL_INTERVAL_MS);
    }
    return this.findDiagnosticEvent(context, since, predicate);
  }

  private async findDiagnosticEvent(
    context: common.Context,
    since: number,
    predicate: (event: DiagnosticEvent) => boolean
  ): Promise<DiagnosticEvent | null> {
    const events = await DiagnosticLog.read(context, 120);
    for (let index = 0; index < events.length; index++) {
      const event = events[index];
      if (event.at >= since && predicate(event)) {
        return event;
      }
    }
    return null;
  }

  private sleep(durationMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, durationMs);
    });
  }

  private formatDiagnosticEvent(event: DiagnosticEvent): string {
    if (event.details !== undefined && event.details.length > 0) {
      return `${event.message} ${event.details}`;
    }
    return event.message;
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
