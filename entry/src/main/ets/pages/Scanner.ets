import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SUBSCRIPTIONS_CONTROLLER } from '../features/subscriptions/SubscriptionsController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct ScannerPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private importBuffer: string = '';
  @State private lastError: string = '';
  @State private isBusy: boolean = false;
  @State private selectedNodeId: string = '';

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.scanner.title'),
        summary: this.t('placeholder.scannerPayload'),
        showBack: true
      })
      Scroll() {
        Column({ space: 12 }) {
          TextArea({
            placeholder: this.t('placeholder.scannerPayload'),
            text: this.importBuffer
          })
            .height(180)
            .fontSize(13)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .padding(10)
            .onChange((value: string) => {
              this.importBuffer = value;
            })

          if (this.lastError.length > 0) {
            Text(this.lastError)
              .fontSize(12)
              .fontColor('#B42318')
              .width('100%')
              .padding(10)
              .backgroundColor('#FEF3F2')
              .borderRadius(6)
          }

          Button(this.t('action.importResult'))
            .height(40)
            .width('100%')
            .enabled(!this.isBusy)
            .backgroundColor('#166534')
            .fontColor('#FFFFFF')
            .borderRadius(8)
            .onClick(() => {
              this.importResult();
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
    this.selectedNodeId = (await NODES_CONTROLLER.load(context, this.language)).selectedNodeId;
  }

  private async importResult(): Promise<void> {
    const value = this.importBuffer.trim();
    if (value.length === 0) {
      this.lastError = this.t('error.emptyImport');
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
      return;
    }

    this.isBusy = true;
    try {
      const context = getContext(this) as common.Context;
      if (value.toLowerCase().startsWith('http://') || value.toLowerCase().startsWith('https://')) {
        const state = await SUBSCRIPTIONS_CONTROLLER.update(context, '', value, this.selectedNodeId, this.language);
        SHARED_RUNTIME_CONTROLLER.appendLog(state.subscriptionMessage);
        router.pushUrl({ url: AppRoute.SUBSCRIPTIONS });
        return;
      }

      const saved = await NODES_CONTROLLER.saveProfile(context, value, this.language);
      if (saved.profile === null) {
        this.lastError = saved.lastError;
        SHARED_RUNTIME_CONTROLLER.appendLog(saved.lastError);
        return;
      }
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.profileSaved'));
      router.back();
    } catch (error) {
      this.lastError = this.f1('error.saveProfile', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    } finally {
      this.isBusy = false;
    }
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
