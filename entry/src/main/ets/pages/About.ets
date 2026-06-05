import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

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
        Column({ space: Space.lg }) {
          // Logo 与版本区
          Column({ space: Space.sm }) {
            Column() {
              Image($r('app.media.startIcon'))
                .width(64)
                .height(64)
                .borderRadius(14)
            }
            .width(88)
            .height(88)
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.xl)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: Space.sm })

            Text('Hey')
              .fontSize(FontSz.title)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.textPrimary)

            Text(this.t('about.section.detail'))
              .fontSize(FontSz.body)
              .fontColor(AppColor.textSecondary)
              .textAlign(TextAlign.Center)
              .padding({ left: Space.xxl, right: Space.xxl })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: Space.xxl, bottom: Space.sm })

          // 资源与更新
          SectionHeader({ title: '资源与更新' })
          Column() {
            AboutItem({
              title: this.t('about.official.title'),
              detail: this.t('about.official.detail'),
              onAction: () => {
                this.openUrl('https://github.com/popsiclelmlm/Hey', this.t('about.official.title'));
              }
            })
            this.RowDivider()
            AboutItem({
              title: this.t('about.issues.title'),
              detail: this.t('about.issues.detail'),
              onAction: () => {
                this.openUrl('https://github.com/popsiclelmlm/Hey/issues', this.t('about.issues.title'));
              }
            })
            this.RowDivider()
            AboutItem({
              title: this.t('about.update.title'),
              detail: this.t('about.update.detail'),
              isChecking: this.isCheckingUpdate,
              onAction: () => {
                this.checkUpdate();
              }
            })
          }
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .width('100%')
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 技术规格
          SectionHeader({ title: '技术规格' })
          Column() {
            AboutItem({
              title: this.t('about.source.title'),
              detail: this.t('about.source.detail'),
              onAction: () => {
                this.openUrl('https://github.com/2rayng/v2rayNG', this.t('about.source.title'));
              }
            })
            this.RowDivider()
            AboutItem({
              title: this.t('about.core.title'),
              detail: this.t('about.core.detail'),
              onAction: () => {
                this.openUrl('https://github.com/XTLS/Xray-core', this.t('about.core.title'));
              }
            })
            this.RowDivider()
            AboutItem({
              title: this.t('about.license.title'),
              detail: this.t('about.license.detail'),
              onAction: () => {
                SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.presetOpened', 'title', this.t('about.license.title')));
                promptAction.showToast({ message: this.t('about.license.detail') });
              }
            })
          }
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .width('100%')
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 社区与开发者
          SectionHeader({ title: '社区与开发者' })
          Column() {
            AboutItem({
              title: this.t('about.telegram.title'),
              detail: this.t('about.telegram.detail'),
              onAction: () => {
                this.openUrl('https://t.me/HeyClient', this.t('about.telegram.title'));
              }
            })
            this.RowDivider()
            AboutItem({
              title: this.t('about.author.title'),
              detail: this.t('about.author.detail'),
              onAction: () => {
                this.openUrl('https://github.com/popsiclelmlm', this.t('about.author.title'));
              }
            })
          }
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .width('100%')
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 版权信息
          Column({ space: Space.xs }) {
            Text('Made with ❤️ for HarmonyOS NEXT')
              .fontSize(FontSz.caption)
              .fontColor(AppColor.textTertiary)
            Text('Copyright © 2026 Hey Team. All rights reserved.')
              .fontSize(FontSz.caption)
              .fontColor(AppColor.textTertiary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: Space.sm, bottom: Space.lg })
        }
        .width('100%')
        .padding({ top: Space.sm, bottom: Space.xxl })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(AppColor.divider)
      .margin({ left: Space.lg })
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
    Row({ space: Space.md }) {
      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        if (this.detail) {
          Text(this.detail)
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
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
          .color(AppColor.brand)
      } else {
        Image($r('app.media.ic_chevron_right'))
          .width(20)
          .height(20)
          .fillColor(AppColor.textTertiary)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .backgroundColor(this.isPressed ? AppColor.surfaceAlt : AppColor.surface)
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
