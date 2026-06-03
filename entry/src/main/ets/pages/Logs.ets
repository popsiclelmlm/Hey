import { common } from '@kit.AbilityKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, ConnectionStatus, RuntimeStats } from '../core/Profile';
import { RuntimeLogPanel } from '../features/logs/LogPanel';
import { RuntimeStatusPanel } from '../features/runtime/RuntimePanel';
import { RuntimeViewState, SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { PageHeader } from '../shell/PageHeader';
import { formatBytes } from '../utils/Formatters';
import { localizeCoreMessage } from '../utils/LocalizationPresenter';

const EMPTY_STATS: RuntimeStats = {
  uploadBytes: 0,
  downloadBytes: 0,
  xrayRunning: false,
  tun2SocksRunning: false,
  lastMessage: translate(DEFAULT_LANGUAGE, 'runtime.nativeBridgeNotQueried')
};

@Entry
@Component
struct LogsPage {
  private timerId: number = -1;

  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private status: ConnectionStatus = ConnectionStatus.IDLE;
  @State private elapsedText: string = '00:00';
  @State private logs: Array<string> = [];
  @State private stats: RuntimeStats = EMPTY_STATS;

  aboutToAppear(): void {
    this.loadState();
    if (this.timerId < 0) {
      this.timerId = setInterval(() => {
        this.refreshRuntime();
      }, 1000);
    }
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.logs.title'),
        summary: this.t('logs.title'),
        showBack: true
      })
      Scroll() {
        Column({ space: 12 }) {
          RuntimeStatusPanel({
            title: this.t('runtime.title'),
            durationLabel: this.t('runtime.duration'),
            durationValue: this.elapsedText,
            uploadLabel: this.t('runtime.upload'),
            uploadValue: formatBytes(this.stats.uploadBytes),
            downloadLabel: this.t('runtime.download'),
            downloadValue: formatBytes(this.stats.downloadBytes),
            xrayActive: this.stats.xrayRunning,
            tunActive: this.stats.tun2SocksRunning,
            lastMessage: this.localizeCoreMessage(this.stats.lastMessage)
          })
          RuntimeLogPanel({
            title: this.t('logs.title'),
            clearLabel: this.t('action.clear'),
            items: this.logs,
            onClear: () => {
              this.clearLogs();
            }
          })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F6F8FA')
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    await this.refreshRuntime();
  }

  private async refreshRuntime(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.applyRuntimeState(await SHARED_RUNTIME_CONTROLLER.refresh(context, this.language));
  }

  private clearLogs(): void {
    const context = getContext(this) as common.Context;
    this.applyRuntimeState(SHARED_RUNTIME_CONTROLLER.clearLogs(context, this.language));
  }

  private applyRuntimeState(state: RuntimeViewState): void {
    this.status = state.status;
    this.elapsedText = state.elapsedText;
    this.logs = state.logs;
    this.stats = state.stats;
  }

  private localizeCoreMessage(message: string): string {
    return localizeCoreMessage(this.language, message);
  }

  private t(key: string): string {
    return translate(this.language, key);
  }
}
