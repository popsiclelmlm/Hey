import { common } from '@kit.AbilityKit';
import { ActionListItem } from '../components/ActionListItem';
import { SectionHeader } from '../components/SectionHeader';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct AssetsPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.assets.title'),
        summary: this.t('assets.section.detail'),
        showBack: true
      })
      Scroll() {
        Column({ space: 12 }) {
          SectionHeader({ title: this.t('assets.section'), detail: this.t('assets.section.detail') })
          this.RowItem('geosite.dat', this.t('assets.geosite.detail'))
          this.RowItem('geoip.dat', this.t('assets.geoip.detail'))
          this.RowItem(this.t('assets.userUrls.title'), this.t('assets.userUrls.detail'))
          this.RowItem(this.t('assets.backupRestore.title'), this.t('assets.backupRestore.detail'))
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
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
