import { common } from '@kit.AbilityKit';
import { ActionListItem } from '../components/ActionListItem';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { SettingToggleRow } from '../features/settings/SettingsControls';
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct PerAppPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private perAppProxyEnabled: boolean = false;
  private draft: SettingsDraft | null = null;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.perApp.title'),
        summary: this.t('settings.vpn.detail'),
        showBack: true
      })
      Scroll() {
        Column({ space: 12 }) {
          SettingToggleRow({
            title: this.t('settings.perAppProxy'),
            settingKey: 'pref_per_app_proxy',
            isEnabled: this.perAppProxyEnabled,
            action: 'perApp',
            onLabel: this.t('action.on'),
            offLabel: this.t('action.off'),
            onToggle: (_action: string) => {
              this.togglePerApp();
            }
          })
          this.RowItem(this.t('perApp.proxySelected.title'), this.t('perApp.proxySelected.detail'))
          this.RowItem(this.t('perApp.bypassSelected.title'), this.t('perApp.bypassSelected.detail'))
          this.RowItem(this.t('perApp.systemVisibility.title'), this.t('perApp.systemVisibility.detail'))
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

  @Builder
  private RowItem(title: string, detail: string) {
    ActionListItem({
      title,
      detail,
      actionLabel: this.t('action.open'),
      onAction: (openedTitle: string) => {
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.presetOpened', 'title', openedTitle));
      }
    })
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.draft = SETTINGS_CONTROLLER.toDraft(await SETTINGS_CONTROLLER.load(context));
    this.language = this.draft.language;
    this.perAppProxyEnabled = this.draft.perAppProxyEnabled;
  }

  private async togglePerApp(): Promise<void> {
    if (this.draft === null) {
      return;
    }
    this.perAppProxyEnabled = !this.perAppProxyEnabled;
    this.draft.perAppProxyEnabled = this.perAppProxyEnabled;
    const context = getContext(this) as common.Context;
    this.draft = SETTINGS_CONTROLLER.toDraft(await SETTINGS_CONTROLLER.save(context, this.draft));
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', 'perApp'));
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
