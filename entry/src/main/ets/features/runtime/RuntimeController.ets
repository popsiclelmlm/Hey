import { common } from '@kit.AbilityKit';
import { DEFAULT_LANGUAGE, translate } from '../../core/I18n';
import { shouldExposeLocalHttpProxy } from '../../core/LocalProxy';
import { APP_MODE_PROXY_ONLY, APP_MODE_VPN, AppLanguage, AppRuntimeMode, AppSettings, ConnectionStatus, normalizeAppRuntimeMode, ProxyProfile, RuntimeStats } from '../../core/Profile';
import { LOCAL_HTTP_PROXY_PORT } from '../../core/XrayConfig';
import { CoreSelectionStore, isSingboxCore } from '../../core/CoreSelection';
import { ConnectionController, ConnectionSnapshot } from '../../services/ConnectionController';
import { DiagnosticEvent, DiagnosticLog } from '../../services/DiagnosticLog';
import { clearCoreLog, readCoreLogEntries } from '../../services/CoreLogReader';
import { LogEntry, normalizeLogLevel } from '../logs/LogModel';
import { fetchRemoteIpInfo, RemoteIpInfoResult } from '../../services/RemoteIpInfo';
import { measureRuntimeProfileDelay, RuntimeDelayResult } from '../../services/RuntimeDelay';
import { connectionStatusBackground, connectionStatusColor, formatClockTime, formatDuration } from '../../utils/Formatters';
import { formatOne, localizedConnectionStatus, localizeCoreMessage, localizeDiagnosticHeartbeat } from '../../utils/LocalizationPresenter';

const EMPTY_STATS: RuntimeStats = {
  uploadBytes: 0,
  downloadBytes: 0,
  xrayRunning: false,
  tunRunning: false,
  lastMessage: translate(DEFAULT_LANGUAGE, 'runtime.nativeBridgeNotQueried')
};

export interface RuntimeViewState {
  status: ConnectionStatus;
  startedAt: number;
  elapsedText: string;
  lastError: string;
  entries: Array<LogEntry>;
  stats: RuntimeStats;
}

export class RuntimeController {
  private controller: ConnectionController = new ConnectionController();
  private status: ConnectionStatus = ConnectionStatus.IDLE;
  private startedAt: number = 0;
  private elapsedText: string = '00:00';
  private lastError: string = '';
  private logs: Array<LogEntry> = RuntimeController.buildReadyLogs();
  private diagnosticEntries: Array<LogEntry> = [];
  private coreEntries: Array<LogEntry> = [];
  private stats: RuntimeStats = EMPTY_STATS;
  private diagnosticRefreshing: boolean = false;
  private runtimeMode: AppRuntimeMode = APP_MODE_VPN;
  // 当前运行内核名（Xray / sing-box），心跳日志据此渲染。
  private coreLabel: string = 'Xray';

  async start(context: common.Context, profile: ProxyProfile, settings: AppSettings, language: AppLanguage): Promise<RuntimeViewState> {
    this.runtimeMode = normalizeAppRuntimeMode(settings.mode, APP_MODE_VPN);
    this.appendLog(this.runtimeMode === APP_MODE_PROXY_ONLY ? translate(language, 'log.startingProxy') : translate(language, 'log.startingVpn'));
    const snapshot = await this.controller.start(context, profile, settings);
    this.applySnapshot(snapshot, language);
    if (this.runtimeMode === APP_MODE_PROXY_ONLY) {
      this.appendLog(this.status === ConnectionStatus.RUNNING ? translate(language, 'log.proxyStarted') : translate(language, 'log.proxyStartIncomplete'));
    } else {
      this.appendLog(this.status === ConnectionStatus.RUNNING ? translate(language, 'log.vpnStarted') : translate(language, 'log.vpnStartIncomplete'));
    }
    this.scheduleRuntimeConnectivityInfo(context, profile, settings, language, this.startedAt);
    return this.refresh(context, language);
  }

  async stop(context: common.Context, language: AppLanguage): Promise<RuntimeViewState> {
    const stoppingMode = this.runtimeMode;
    this.appendLog(stoppingMode === APP_MODE_PROXY_ONLY ? translate(language, 'log.stoppingProxy') : translate(language, 'log.stoppingVpn'));
    const snapshot = await this.controller.stop(context);
    this.applySnapshot(snapshot, language);
    if (stoppingMode === APP_MODE_PROXY_ONLY) {
      this.appendLog(this.status === ConnectionStatus.IDLE ? translate(language, 'log.proxyStopped') : translate(language, 'log.proxyStopIncomplete'));
    } else {
      this.appendLog(this.status === ConnectionStatus.IDLE ? translate(language, 'log.vpnStopped') : translate(language, 'log.vpnStopIncomplete'));
    }
    if (this.status === ConnectionStatus.IDLE) {
      this.runtimeMode = APP_MODE_VPN;
    }
    return this.refresh(context, language);
  }

  // 运行中按传入的新 Profile 热切换：先停后启。非运行态直接返回当前快照，调用方无需自行判断。
  // 供没有连接管线的页面（如订阅详情）复用，避免「界面显示已切换、隧道仍跑旧配置」。
  async reconnectWithProfile(context: common.Context, profile: ProxyProfile, settings: AppSettings, language: AppLanguage): Promise<RuntimeViewState> {
    if (this.status !== ConnectionStatus.RUNNING) {
      return this.snapshot();
    }
    const stopped = await this.stop(context, language);
    if (stopped.status !== ConnectionStatus.IDLE) {
      return stopped;
    }
    return this.start(context, profile, settings, language);
  }

  async refresh(context: common.Context, language: AppLanguage): Promise<RuntimeViewState> {
    this.stats = this.controller.getStats();
    this.coreLabel = isSingboxCore(await CoreSelectionStore.load(context)) ? 'sing-box' : 'Xray';
    await this.refreshDiagnostics(context, language);
    this.coreEntries = readCoreLogEntries(context.filesDir);
    this.stats = this.localizeStats(this.stats, language);
    if (this.startedAt <= 0 || this.status !== ConnectionStatus.RUNNING) {
      this.elapsedText = '00:00';
      return this.snapshot();
    }
    const seconds = Math.max(0, Math.floor((Date.now() - this.startedAt) / 1000));
    this.elapsedText = formatDuration(seconds);
    return this.snapshot();
  }

  snapshot(): RuntimeViewState {
    return {
      status: this.status,
      startedAt: this.startedAt,
      elapsedText: this.elapsedText,
      lastError: this.lastError,
      entries: this.allEntries(),
      stats: this.stats
    };
  }

  appendLog(message: string): void {
    const entry = RuntimeController.makeAppEntry(message);
    const next = [entry].concat(this.logs);
    this.logs = next.slice(0, 80);
  }

  clearLogs(context: common.Context, language: AppLanguage): RuntimeViewState {
    try {
      DiagnosticLog.clear(context);
    } catch (error) {
      this.appendLog(formatOne(language, 'error.clearDiagnostics', 'error', JSON.stringify(error)));
    }
    this.logs = [];
    this.diagnosticEntries = [];
    clearCoreLog(context.filesDir);
    this.coreEntries = [];
    return this.snapshot();
  }

  statusLabel(language: AppLanguage): string {
    return localizedConnectionStatus(language, this.status);
  }

  statusColor(): string {
    return connectionStatusColor(this.status);
  }

  statusBackground(): string {
    return connectionStatusBackground(this.status);
  }

  isRunning(): boolean {
    return this.status === ConnectionStatus.RUNNING;
  }

  isBusy(): boolean {
    return this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.STOPPING;
  }

  // 核心日志、诊断日志、应用日志各自最新在前，合并后按时间倒序统一排列（最新在顶），上限 120 条。
  private allEntries(): Array<LogEntry> {
    const merged = this.coreEntries.concat(this.diagnosticEntries).concat(this.logs);
    merged.sort((a: LogEntry, b: LogEntry) => b.at - a.at);
    return merged.slice(0, 120);
  }

  // 应用内日志没有等级信息，统一记为 info；raw 保留「时钟 + 正文」整行原文。
  private static makeAppEntry(message: string): LogEntry {
    const at = Date.now();
    const time = formatClockTime(at);
    return { at, time, level: 'info', source: '', message, raw: `${time}  ${message}` };
  }

  private static buildReadyLogs(): Array<LogEntry> {
    return [RuntimeController.makeAppEntry(translate(DEFAULT_LANGUAGE, 'log.ready'))];
  }

  // 诊断事件本身带 level/source，归一化等级。心跳（vpn-stats）渲染成带流量/状态的友好文案，
  // 其余沿用既有格式化输出（供复制/分享）。
  private static eventToEntry(event: DiagnosticEvent, language: AppLanguage, coreLabel: string): LogEntry {
    const time = formatClockTime(event.at);
    const level = normalizeLogLevel(event.level);
    if (event.source === 'vpn-stats') {
      const message = localizeDiagnosticHeartbeat(
        language,
        event.uploadBytes ?? 0,
        event.downloadBytes ?? 0,
        event.xrayRunning ?? false,
        event.tunRunning ?? false,
        coreLabel
      );
      return { at: event.at, time, level, source: event.source, message, raw: `${time}  ${message}` };
    }
    return {
      at: event.at,
      time,
      level,
      source: event.source,
      message: event.message,
      raw: DiagnosticLog.format(event, (value: number) => formatClockTime(value))
    };
  }

  private localizeStats(stats: RuntimeStats, language: AppLanguage): RuntimeStats {
    return {
      uploadBytes: stats.uploadBytes,
      downloadBytes: stats.downloadBytes,
      xrayRunning: stats.xrayRunning,
      tunRunning: stats.tunRunning,
      lastMessage: localizeCoreMessage(language, stats.lastMessage)
    };
  }

  private applySnapshot(snapshot: ConnectionSnapshot, language: AppLanguage): void {
    this.status = snapshot.status;
    this.startedAt = snapshot.startedAt;
    this.lastError = localizeCoreMessage(language, snapshot.lastError);
  }

  private scheduleRuntimeConnectivityInfo(
    context: common.Context,
    profile: ProxyProfile,
    settings: AppSettings,
    language: AppLanguage,
    startedAt: number
  ): void {
    this.appendRuntimeConnectivityInfo(context, profile, settings, language, startedAt).catch((error: Object) => {
      this.appendLog(formatOne(language, 'log.connectionDelayError', 'error', JSON.stringify(error)));
    });
  }

  private async appendRuntimeConnectivityInfo(
    context: common.Context,
    profile: ProxyProfile,
    settings: AppSettings,
    language: AppLanguage,
    startedAt: number
  ): Promise<void> {
    if (this.status !== ConnectionStatus.RUNNING || this.startedAt !== startedAt) {
      return;
    }
    const delayResult: RuntimeDelayResult = await measureRuntimeProfileDelay(profile, context.filesDir, settings.delayTestUrl);
    if (this.status !== ConnectionStatus.RUNNING || this.startedAt !== startedAt) {
      return;
    }
    if (delayResult.ok) {
      this.appendLog(formatOne(language, 'log.connectionDelay', 'delay', delayResult.delayMs.toString()));
      await this.appendRemoteIpInfo(profile, settings, language, startedAt);
      return;
    }
    if (delayResult.status === 'unsupported-config') {
      await this.appendRemoteIpInfo(profile, settings, language, startedAt);
      return;
    }
    this.appendLog(formatOne(language, 'log.connectionDelayError', 'error', delayResult.status));
  }

  private async appendRemoteIpInfo(profile: ProxyProfile, settings: AppSettings, language: AppLanguage, startedAt: number): Promise<void> {
    if (this.status !== ConnectionStatus.RUNNING || this.startedAt !== startedAt || !shouldExposeLocalHttpProxy(settings) ||
      (profile.configType ?? 'outbound') === 'full') {
      return;
    }
    const result: RemoteIpInfoResult = await fetchRemoteIpInfo(settings.ipApiUrl, LOCAL_HTTP_PROXY_PORT);
    if (this.status === ConnectionStatus.RUNNING && this.startedAt === startedAt && result.ok && result.summary.length > 0) {
      this.appendLog(formatOne(language, 'log.remoteIpInfo', 'info', result.summary));
    }
  }

  private async refreshDiagnostics(context: common.Context, language: AppLanguage): Promise<void> {
    if (this.diagnosticRefreshing) {
      return;
    }
    this.diagnosticRefreshing = true;

    try {
      const events = await DiagnosticLog.read(context, 80);
      this.diagnosticEntries = events.map((event: DiagnosticEvent) => RuntimeController.eventToEntry(event, language, this.coreLabel));
      this.applyDiagnosticStats(events);
      this.applyDiagnosticError(events, language);
    } catch (error) {
      // 诊断解析失败绝不能让 refresh 整体抛出——否则页面收不到 snapshot，日志面板会全空。
      console.error(`Diagnostic refresh failed: ${JSON.stringify(error)}`);
    } finally {
      this.diagnosticRefreshing = false;
    }
  }

  private applyDiagnosticStats(events: Array<DiagnosticEvent>): void {
    for (let index = 0; index < events.length; index++) {
      const event = events[index];
      if (event.uploadBytes !== undefined || event.downloadBytes !== undefined) {
        this.stats = {
          uploadBytes: event.uploadBytes ?? 0,
          downloadBytes: event.downloadBytes ?? 0,
          xrayRunning: event.xrayRunning ?? false,
          tunRunning: event.tunRunning ?? false,
          lastMessage: event.details ?? event.message
        };
        return;
      }
    }
  }

  private applyDiagnosticError(events: Array<DiagnosticEvent>, language: AppLanguage): void {
    if (events.length === 0) {
      return;
    }
    const event = events[0];
    if (event.level !== 'error') {
      return;
    }
    const message = event.details !== undefined && event.details.length > 0 ? `${event.message} ${event.details}` : event.message;
    this.lastError = localizeCoreMessage(language, message);
    if (this.status === ConnectionStatus.RUNNING || this.status === ConnectionStatus.STARTING) {
      this.status = ConnectionStatus.ERROR;
    }
  }
}

export const SHARED_RUNTIME_CONTROLLER: RuntimeController = new RuntimeController();
