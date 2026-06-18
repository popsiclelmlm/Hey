import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

@Entry
@Component
struct JsonImportPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private outboundJson: string = '';
  @State private validationMessage: string = '';
  @State private validationOk: boolean = false;
  @State private isBusy: boolean = false;
  @State private lastError: string = '';

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: translate(this.language, 'screen.jsonImport.title'),
        showBack: true
      })

      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: Space.lg }) {
            // 输入卡片
            SectionHeader({ title: 'Xray JSON 配置' })
            Column() {
              // 粘贴 / 清空 操作行
              Row({ space: Space.sm }) {
                Blank()
                Button('粘贴')
                  .fontSize(FontSz.footnote)
                  .fontColor(AppColor.brand)
                  .backgroundColor(AppColor.brandTint)
                  .height(30)
                  .padding({ left: Space.md, right: Space.md })
                  .borderRadius(Radius.sm)
                  .onClick(() => {
                    this.pasteFromClipboard();
                  })

                if (this.outboundJson.length > 0) {
                  Button('清空')
                    .fontSize(FontSz.footnote)
                    .fontColor(AppColor.danger)
                    .backgroundColor(AppColor.dangerTint)
                    .height(30)
                    .padding({ left: Space.md, right: Space.md })
                    .borderRadius(Radius.sm)
                    .onClick(() => {
                      this.outboundJson = '';
                      this.validateConfig();
                    })
                }
              }
              .width('100%')
              .padding({ left: Space.lg, right: Space.lg, top: Space.md })

              TextArea({
                placeholder: '请粘贴 Xray outbound JSON 或完整 Xray config，例如：\n{\n  "inbounds": [ ... ],\n  "outbounds": [ ... ]\n}',
                text: this.outboundJson
              })
                .height(260)
                .width('100%')
                .fontSize(FontSz.body)
                .fontColor(AppColor.textPrimary)
                .fontFamily('monospace')
                .backgroundColor(Color.Transparent)
                .borderRadius(0)
                .padding(Space.lg)
                .onChange((value: string) => {
                  this.outboundJson = value;
                  this.validateConfig();
                })
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })

            Text('注意：可导入单个 outbound（包含 protocol/settings），也可导入完整配置（包含 inbounds/outbounds）。')
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.textTertiary)
              .width('100%')
              .lineHeight(16)
              .padding({ left: Space.lg + Space.xs, right: Space.lg + Space.xs })

            // 校验结果指示板
            if (this.outboundJson.trim().length > 0) {
              Column({ space: Space.sm }) {
                Row({ space: Space.sm }) {
                  Column()
                    .width(6)
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(this.validationOk ? AppColor.success : AppColor.danger)

                  Text(this.validationOk ? '配置格式有效' : '配置格式无效')
                    .fontSize(FontSz.body)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.validationOk ? AppColor.success : AppColor.danger)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Text(this.validationMessage)
                  .fontSize(FontSz.footnote)
                  .fontColor(this.validationOk ? AppColor.success : AppColor.danger)
                  .width('100%')
                  .lineHeight(16)
              }
              .width('100%')
              .padding(Space.lg)
              .backgroundColor(this.validationOk ? AppColor.successTint : AppColor.dangerTint)
              .borderRadius(Radius.md)
              .margin({ left: Space.lg, right: Space.lg })
            }

            if (this.lastError.length > 0) {
              Text(this.lastError)
                .fontSize(FontSz.footnote)
                .fontColor(AppColor.danger)
                .width('100%')
                .padding(Space.md)
                .backgroundColor(AppColor.dangerTint)
                .borderRadius(Radius.md)
                .margin({ left: Space.lg, right: Space.lg })
            }
          }
          .width('100%')
          .padding({ top: Space.sm, bottom: 100 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)

        // 底部保存按钮
        Column() {
          Button() {
            Row() {
              if (this.isBusy) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColor.onBrand)
                  .margin({ right: Space.sm })
              }
              Text('导入此 JSON 配置')
                .fontSize(FontSz.headline)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isSaveEnabled() ? AppColor.onBrand : AppColor.textTertiary)
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(Radius.pill)
          .enabled(this.isSaveEnabled())
          .backgroundColor(this.isSaveEnabled() ? AppColor.brand : AppColor.surfaceAlt)
          .onClick(() => {
            this.importJsonNode();
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.xxl })
        .backgroundColor(AppColor.bg)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  private isSaveEnabled(): boolean {
    return this.outboundJson.trim().length > 0 && this.validationOk && !this.isBusy;
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    this.validateConfig();
  }

  private validateConfig(): void {
    const value = this.outboundJson.trim();
    if (value.length === 0) {
      this.validationOk = false;
      this.validationMessage = '';
      return;
    }
    const validation = NODES_CONTROLLER.validateConfig(value, this.language);
    this.validationOk = validation.valid;
    this.validationMessage = validation.message;
  }

  private async importJsonNode(): Promise<void> {
    const value = this.outboundJson.trim();
    if (value.length === 0 || !this.validationOk) {
      return;
    }

    this.isBusy = true;
    try {
      const context = getContext(this) as common.Context;
      const validation = NODES_CONTROLLER.validateConfig(value, this.language);
      if (!validation.valid) {
        this.lastError = validation.message;
        return;
      }

      const normalizedJson = validation.normalizedJson;
      // 提取 JSON 中 tag 字段作为节点名，若无则使用默认名称
      let nodeName = validation.configType === 'full' ? '完整配置导入' : 'JSON导入';
      try {
        const obj = JSON.parse(normalizedJson) as Record<string, Object>;
        if (obj.tag && typeof obj.tag === 'string' && obj.tag.trim().length > 0) {
          nodeName = obj.tag.trim();
        } else if (validation.configType === 'full' && obj.remarks && typeof obj.remarks === 'string' && obj.remarks.trim().length > 0) {
          nodeName = obj.remarks.trim();
        } else if (validation.configType === 'full' && obj.name && typeof obj.name === 'string' && obj.name.trim().length > 0) {
          nodeName = obj.name.trim();
        }
      } catch (err) {
        // ignore
      }

      const savedProfile = await NODES_CONTROLLER.saveProfile(context, normalizedJson, this.language, validation.configType);
      if (savedProfile.profile === null) {
        this.lastError = savedProfile.lastError;
        return;
      }

      await SubscriptionStore.addManualNode(context, nodeName, normalizedJson, validation.configType);
      SHARED_RUNTIME_CONTROLLER.appendLog('自定义 JSON 节点导入成功');
      promptAction.showToast({ message: '节点导入成功' });
      router.back();
    } catch (error) {
      this.lastError = '导入失败：' + JSON.stringify(error);
    } finally {
      this.isBusy = false;
    }
  }

  private async pasteFromClipboard() {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (systemPasteboard.hasDataSync()) {
        const pasteData = await systemPasteboard.getData();
        const text = pasteData.getPrimaryText();
        if (text && text.trim().length > 0) {
          this.outboundJson = text.trim();
          this.validateConfig();
          promptAction.showToast({ message: '已粘贴 JSON 配置' });
        } else {
          promptAction.showToast({ message: '剪贴板未发现有效文本' });
        }
      } else {
        promptAction.showToast({ message: '剪贴板为空' });
      }
    } catch (error) {
      promptAction.showToast({ message: '无法读取剪贴板' });
    }
  }
}
