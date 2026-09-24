import { common } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { APP_MODE_PROXY_ONLY, APP_MODE_VPN, AppRuntimeMode, AppSettings, ConnectionStatus, GeneratedXrayConfig, normalizeAppRuntimeMode, ProxyProfile, RuntimeStats } from '../core/Profile';
import { resolveDynamicPolicyGroupConfigJson } from '../core/AdvancedOutboundBuilder';
import { selectRuntimeLocalSocksPort, shouldExposeLocalHttpProxy, shouldUseDynamicLocalSocksPort, withRuntimeLocalSocksPort } from '../core/LocalProxy';
import { buildRuntimeXrayConfig, injectXrayLogFile, LOCAL_HTTP_PROXY_PORT, METRICS_PORT, normalizeConfigInput, XRAY_CORE_LOG_FILE } from '../core/XrayConfig';
import { normalizeCoreLogLevel } from '../core/ProtocolOptions';
import { CORE_TYPE_SINGBOX, CORE_TYPE_XRAY, CoreSelectionStore, CoreType, isSingboxCore, isSingboxOnlyProtocol } from '../core/CoreSelection';
import { buildSingboxConfig } from '../core/SingboxConfig';
import { credentialsFromRandomBytes, DATA_PLANE_RANDOM_BYTES, SecuredDataPlaneConfig, secureDataPlaneInbound } from '../core/DataPlaneAuth';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { createStopCommandVpnWant, createStopVpnWant, createVpnWant } from '../vpn/VpnConstants';
import { getNativeFreePorts, getNativeStats, startNativeXray, stopNativeXray, testNativeXrayConfig } from '../native/HeyNative';
import { DiagnosticEvent, DiagnosticLog } from './DiagnosticLog';
import { clearCoreLog, clearSingboxLog } from './CoreLogReader';
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
  // 本次连接实际使用的内核（可能因 anytls/tuic 被强制切到 sing-box）。
  coreType: CoreType;
}

export class ConnectionController {
  private status: ConnectionStatus = ConnectionStatus.IDLE;
  private startedAt: number = 0;
  private lastError: string = '';
  private generatedConfig: GeneratedXrayConfig | null = null;
  private runtimeMode: AppRuntimeMode = APP_MODE_VPN;
  // 本次连接实际使用的内核（anytls/tuic 会强制走 sing-box，与全局开关可能不一致）。
  private effectiveCoreType: CoreType = CORE_TYPE_XRAY;

  getSnapshot(): ConnectionSnapshot {
    return {
      status: this.status,
      startedAt: this.startedAt,
      lastError: this.lastError,
      generatedConfig: this.generatedConfig,
      coreType: this.effectiveCoreType
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

    // 内核分流：sing-box（预览）走独立的配置生成 + native 生命周期。
    // anytls / tuic 等 sing-box 独有协议 Xray 没有对应 outbound，无论全局开关如何都强制走 sing-box。
    const coreType = await CoreSelectionStore.load(context);
    const forceSingbox = validation.configType === 'outbound' && isSingboxOnlyProtocol(validation.protocol);
    const useSingbox = isSingboxCore(coreType) || forceSingbox;
    this.effectiveCoreType = useSingbox ? CORE_TYPE_SINGBOX : CORE_TYPE_XRAY;
    if (useSingbox) {
      return this.startSingbox(context, validation.normalizedJson, validation.configType, settings);
    }

    const runtimeSettings = validation.configType === 'full' ? settings : this.resolveRuntimeSettings(settings);
    const runtimeConfigJson = await this.resolveRuntimeConfigJson(context, validation.normalizedJson, validation.configType);
    const resolvedRuntimeSettings = await OUTBOUND_DOMAIN_RESOLVER.resolve(context, runtimeConfigJson, runtimeSettings, validation.configType);
    this.generatedConfig = buildRuntimeXrayConfig(runtimeConfigJson, resolvedRuntimeSettings, validation.configType);
    // 让核心把分级运行日志落盘，供 Logcat 页读取（绝对路径，VPN 扩展进程与主进程共享沙箱）。
    // 启动前清空旧文件：核心日志本就是逐会话的，避免跨会话累积、文件无限增长。
    clearCoreLog(context.filesDir);
    const coreLogPath = `${context.filesDir}/${XRAY_CORE_LOG_FILE}`;
    const fallbackLogLevel = normalizeCoreLogLevel(resolvedRuntimeSettings?.logLevel ?? '');
    this.generatedConfig.configJson = injectXrayLogFile(this.generatedConfig.configJson, coreLogPath, fallbackLogLevel);
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
      const dataPlane = this.secureVpnDataPlane(this.generatedConfig.configJson, false);
      await this.withTimeout(vpnExtension.startVpnExtensionAbility(createVpnWant(
        dataPlane.configJson,
        CORE_TYPE_XRAY,
        dataPlane.credentials
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

  // sing-box 内核启动路径（预览）：仅支持 VPN 模式 + 单节点（outbound）配置。
  private async startSingbox(
    context: common.Context,
    normalizedJson: string,
    configType: string | undefined,
    settings?: AppSettings
  ): Promise<ConnectionSnapshot> {
    const mode = normalizeAppRuntimeMode(settings?.mode, APP_MODE_VPN);
    if (mode === APP_MODE_PROXY_ONLY) {
      this.status = ConnectionStatus.ERROR;
      this.lastError = 'sing-box 预览暂仅支持 VPN 模式，请切回 VPN 模式或改用 Xray 内核。';
      return this.getSnapshot();
    }
    if (configType !== undefined && configType !== 'outbound') {
      this.status = ConnectionStatus.ERROR;
      this.lastError = 'sing-box 预览暂仅支持单节点配置（不支持代理链 / 策略组 / 完整配置）。';
      return this.getSnapshot();
    }

    clearSingboxLog(context.filesDir);
    const generated = buildSingboxConfig(normalizedJson, settings, context.filesDir);
    if (!generated.ok) {
      this.status = ConnectionStatus.ERROR;
      this.lastError = generated.message;
      return this.getSnapshot();
    }

    this.generatedConfig = { configJson: generated.configJson };
    this.runtimeMode = APP_MODE_VPN;
    const requestedAt = Date.now();
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Calling startVpnExtensionAbility (sing-box), configBytes=%{public}d',
        generated.configJson.length);
      const dataPlane = this.secureVpnDataPlane(generated.configJson, true);
      await this.withTimeout(vpnExtension.startVpnExtensionAbility(createVpnWant(
        dataPlane.configJson,
        CORE_TYPE_SINGBOX,
        dataPlane.credentials
      )), START_VPN_TIMEOUT_MS, '启动 VPN 超时：系统 VPN 授权服务没有响应。若为模拟器缺少 VPN 授权组件，请改用真机测试。');
      const startEvent = await this.waitForDiagnosticEvent(context, requestedAt, START_VPN_READY_TIMEOUT_MS, (event: DiagnosticEvent) => {
        return event.source === 'vpn' && (event.message === VPN_STARTED_MESSAGE || event.message === VPN_START_FAILED_MESSAGE);
      });
      if (startEvent === null) {
        throw new Error('启动 sing-box 未确认完成：VPN 扩展没有回写启动完成状态。');
      }
      if (startEvent.message === VPN_START_FAILED_MESSAGE) {
        throw new Error(this.formatDiagnosticEvent(startEvent));
      }
      this.status = ConnectionStatus.RUNNING;
      this.startedAt = Date.now();
    } catch (error) {
      const businessError = error as BusinessError;
      this.status = ConnectionStatus.ERROR;
      this.lastError = `启动 sing-box 失败：${businessError.message ?? JSON.stringify(error)}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'sing-box start failed: %{public}s', this.lastError);
    }
    return this.getSnapshot();
  }

  // 给这次会话的数据面入站加随机凭据。只作用于交给 VPN 扩展的那份配置，generatedConfig 快照不带凭据。
  // 取不到安全随机数时退回无认证（与此前行为一致），不让 VPN 因此起不来。
  private secureVpnDataPlane(configJson: string, useSingbox: boolean): SecuredDataPlaneConfig {
    try {
      const random = cryptoFramework.createRandom();
      const credentials = credentialsFromRandomBytes(random.generateRandomSync(DATA_PLANE_RANDOM_BYTES).data);
      const secured = secureDataPlaneInbound(configJson, useSingbox, credentials);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'VPN data plane auth: %{public}s', secured.credentials !== undefined ? 'on' : 'off');
      return secured;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'VPN data plane auth unavailable: %{public}s', JSON.stringify(error));
      return { configJson };
    }
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
    if (shouldExposeLocalHttpProxy(settings)) {
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

  // 隧道已被 VPN 扩展在后台自动断开（网络场景），本进程状态滞留「运行中」时校正为空闲。
  // 不下发停止命令（隧道已不存在）。仅在自认为运行/启动中时生效。
  reconcileStopped(): ConnectionSnapshot {
    if (this.status === ConnectionStatus.RUNNING || this.status === ConnectionStatus.STARTING) {
      this.status = ConnectionStatus.IDLE;
      this.startedAt = 0;
      this.lastError = '';
      this.runtimeMode = APP_MODE_VPN;
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
