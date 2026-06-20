import { common } from '@kit.AbilityKit';
import { DEFAULT_LANGUAGE, translate } from '../../core/I18n';
import { shouldExposeLocalHttpProxy } from '../../core/LocalProxy';
import { APP_MODE_PROXY_ONLY, APP_MODE_VPN, AppLanguage, AppRuntimeMode, AppSettings, ConnectionStatus, normalizeAppRuntimeMode, ProxyProfile, RuntimeStats } from '../../core/Profile';
import { LOCAL_HTTP_PROXY_PORT } from '../../core/XrayConfig';
import { ConnectionController, ConnectionSnapshot } from '../../services/ConnectionController';
import { DiagnosticEvent, DiagnosticLog } from '../../services/DiagnosticLog';
import { fetchRemoteIpInfo, RemoteIpInfoResult } from '../../services/RemoteIpInfo';
import { connectionStatusBackground, connectionStatusColor, formatClockTime, formatDuration } from '../../utils/Formatters';
import { formatOne, localizedConnectionStatus, localizeCoreMessage } from '../../utils/LocalizationPresenter';

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
  logs: Array<string>;
  stats: RuntimeStats;
}

export class RuntimeController {
  private controller: ConnectionController = new ConnectionController();
  private status: ConnectionStatus = ConnectionStatus.IDLE;
  private startedAt: number = 0;
  private elapsedText: string = '00:00';
  private lastError: string = '';
  private logs: Array<string> = [translate(DEFAULT_LANGUAGE, 'log.ready')];
  private diagnosticLogs: Array<string> = [];
  private stats: RuntimeStats = EMPTY_STATS;
  private diagnosticRefreshing: boolean = false;
  private runtimeMode: AppRuntimeMode = APP_MODE_VPN;

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
    await this.appendRemoteIpInfo(profile, settings, language);
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

  async refresh(context: common.Context, language: AppLanguage): Promise<RuntimeViewState> {
    this.stats = this.controller.getStats();
    await this.refreshDiagnostics(context, language);
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
      logs: this.allLogs(),
      stats: this.stats
    };
  }

  appendLog(message: string): void {
    const line = `${formatClockTime(Date.now())}  ${message}`;
    const next = [line].concat(this.logs);
    this.logs = next.slice(0, 80);
  }

  clearLogs(context: common.Context, language: AppLanguage): RuntimeViewState {
    try {
      DiagnosticLog.clear(context);
    } catch (error) {
      this.appendLog(formatOne(language, 'error.clearDiagnostics', 'error', JSON.stringify(error)));
    }
    this.logs = [];
    this.diagnosticLogs = [];
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

  private allLogs(): Array<string> {
    return this.diagnosticLogs.concat(this.logs).slice(0, 120);
  }

  private applySnapshot(snapshot: ConnectionSnapshot, language: AppLanguage): void {
    this.status = snapshot.status;
    this.startedAt = snapshot.startedAt;
    this.lastError = localizeCoreMessage(language, snapshot.lastError);
  }

  private async appendRemoteIpInfo(profile: ProxyProfile, settings: AppSettings, language: AppLanguage): Promise<void> {
    if (this.status !== ConnectionStatus.RUNNING || !shouldExposeLocalHttpProxy(settings) ||
      (profile.configType ?? 'outbound') === 'full') {
      return;
    }
    const result: RemoteIpInfoResult = await fetchRemoteIpInfo(settings.ipApiUrl, LOCAL_HTTP_PROXY_PORT);
    if (result.ok && result.summary.length > 0) {
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
      this.diagnosticLogs = events.map((event: DiagnosticEvent) => DiagnosticLog.format(event, (value: number) => formatClockTime(value)));
      this.applyDiagnosticStats(events);
      this.applyDiagnosticError(events, language);
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
