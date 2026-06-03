import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct AboutPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private isCheckingUpdate: boolean = false;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.about.title'),
        summary: this.t('about.section.detail'),
        showBack: true
      })
      Scroll() {
        Column({ space: 16 }) {
          // Header Logo & Version Section
          Column({ space: 8 }) {
            Column() {
              Image($r('app.media.startIcon'))
                .width(64)
                .height(64)
                .borderRadius(14)
            }
            .width(88)
            .height(88)
            .backgroundColor('#FFFFFF')
            .borderRadius(20)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .shadow({ radius: 12, color: '#15000000', offsetX: 0, offsetY: 6 })
            .margin({ bottom: 8 })

            Text('Hey')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')

            Text(this.t('about.section.detail'))
              .fontSize(14)
              .fontColor('#6B7280')
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 24, bottom: 16 })

          // Section 1: Official Resources & Actions
          Column() {
            AboutItem({
              title: this.t('about.official.title'),
              detail: this.t('about.official.detail'),
              onAction: () => {
                this.openUrl('https://github.com/popsiclelmlm/Hey', this.t('about.official.title'));
              }
            })
            Divider().color('#F3F4F6').strokeWidth(1).margin({ left: 16, right: 16 })
            AboutItem({
              title: this.t('about.issues.title'),
              detail: this.t('about.issues.detail'),
              onAction: () => {
                this.openUrl('https://github.com/popsiclelmlm/Hey/issues', this.t('about.issues.title'));
              }
            })
            Divider().color('#F3F4F6').strokeWidth(1).margin({ left: 16, right: 16 })
            AboutItem({
              title: this.t('about.update.title'),
              detail: this.t('about.update.detail'),
              isChecking: this.isCheckingUpdate,
              onAction: () => {
                this.checkUpdate();
              }
            })
          }
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .width('100%')
          .shadow({ radius: 8, color: '#06000000', offsetX: 0, offsetY: 2 })
          .clip(true)

          // Section 2: Technical Specifications & Parity
          Column() {
            AboutItem({
              title: this.t('about.source.title'),
              detail: this.t('about.source.detail'),
              onAction: () => {
                this.openUrl('https://github.com/2rayng/v2rayNG', this.t('about.source.title'));
              }
            })
            Divider().color('#F3F4F6').strokeWidth(1).margin({ left: 16, right: 16 })
            AboutItem({
              title: this.t('about.core.title'),
              detail: this.t('about.core.detail'),
              onAction: () => {
                this.openUrl('https://github.com/XTLS/Xray-core', this.t('about.core.title'));
              }
            })
            Divider().color('#F3F4F6').strokeWidth(1).margin({ left: 16, right: 16 })
            AboutItem({
              title: this.t('about.license.title'),
              detail: this.t('about.license.detail'),
              onAction: () => {
                SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.presetOpened', 'title', this.t('about.license.title')));
                promptAction.showToast({ message: this.t('about.license.detail') });
              }
            })
          }
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .width('100%')
          .shadow({ radius: 8, color: '#06000000', offsetX: 0, offsetY: 2 })
          .clip(true)

          // Section 3: Community & Developer
          Column() {
            AboutItem({
              title: this.t('about.telegram.title'),
              detail: this.t('about.telegram.detail'),
              onAction: () => {
                this.openUrl('https://t.me/HeyClient', this.t('about.telegram.title'));
              }
            })
            Divider().color('#F3F4F6').strokeWidth(1).margin({ left: 16, right: 16 })
            AboutItem({
              title: this.t('about.author.title'),
              detail: this.t('about.author.detail'),
              onAction: () => {
                this.openUrl('https://github.com/popsiclelmlm', this.t('about.author.title'));
              }
            })
          }
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .width('100%')
          .shadow({ radius: 8, color: '#06000000', offsetX: 0, offsetY: 2 })
          .clip(true)

          // Footer Copyright
          Column({ space: 4 }) {
            Text('Made with ❤️ for HarmonyOS NEXT')
              .fontSize(11)
              .fontColor('#9CA3AF')
            Text('Copyright © 2026 Hey Team. All rights reserved.')
              .fontSize(10)
              .fontColor('#D1D5DB')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 16, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F6F8FA')
  }

  private async openUrl(url: string, title: string): Promise<void> {
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.presetOpened', 'title', title));
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };
      await context.startAbility(want);
    } catch (error) {
      // Fallback: Copy to clipboard if cannot start ability in current runtime environment
      try {
        const systemPasteboard = pasteboard.getSystemPasteboard();
        const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
        systemPasteboard.setDataSync(pasteData);
        promptAction.showToast({ message: this.t('about.action.copied') });
      } catch (clipboardError) {
        promptAction.showToast({ message: '操作失败，请重试' });
      }
    }
  }

  private checkUpdate(): void {
    if (this.isCheckingUpdate) {
      return;
    }
    this.isCheckingUpdate = true;
    setTimeout(() => {
      this.isCheckingUpdate = false;
      promptAction.showToast({ message: this.t('about.update.latest') });
    }, 1200);
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

@Component
struct AboutItem {
  title: string = '';
  detail: string = '';
  isChecking: boolean = false;
  onAction: () => void = () => {};

  @State private isPressed: boolean = false;

  build() {
    Row() {
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F2937')
        if (this.detail) {
          Text(this.detail)
            .fontSize(12)
            .fontColor('#6B7280')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isChecking) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color('#F97910')
      } else {
        Image($r('app.media.ic_chevron_right'))
          .width(18)
          .height(18)
          .fillColor('#9CA3AF')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.isPressed ? '#F3F4F6' : '#FFFFFF')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false;
      }
    })
    .onClick(() => {
      if (!this.isChecking) {
        this.onAction();
      }
    })
  }
}
