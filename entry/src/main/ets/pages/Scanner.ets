import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SUBSCRIPTIONS_CONTROLLER } from '../features/subscriptions/SubscriptionsController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { SubscriptionStore } from '../storage/SubscriptionStore';

@Entry
@Component
struct ScannerPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private importBuffer: string = '';
  @State private lastError: string = '';
  @State private isBusy: boolean = false;
  @State private selectedNodeId: string = '';
  @State private hasAutoScanned: boolean = false;
  @State private isPressedScanCard: boolean = false;
  @State private isPressedImportBtn: boolean = false;

  aboutToAppear(): void {
    this.loadState();
  }

  onPageShow(): void {
    if (!this.hasAutoScanned) {
      this.hasAutoScanned = true;
      // 延迟 300 毫秒拉起扫码，确保转场动画完全结束后再加载扫码面板，体验更流畅
      setTimeout(() => {
        this.startCameraScan();
      }, 300);
    }
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.scanner.title'),
        showBack: true
      })

      Scroll() {
        Column({ space: 16 }) {
          // 模块一：相机扫码引导卡片
          Column({ space: 12 }) {
            Row() {
              Image($r('app.media.ic_qr_code'))
                .width(28)
                .height(28)
                .fillColor('#F97910')
                .margin({ right: 12 })
              
              Column() {
                Text('相机扫码导入')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#111827')
                Text('点击拉起相机扫码，支持从相册选择二维码图片')
                  .fontSize(12)
                  .fontColor('#6B7280')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Image($r('app.media.ic_chevron_right'))
                .width(18)
                .height(18)
                .fillColor('#9CA3AF')
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 })
          .scale({ x: this.isPressedScanCard ? 0.98 : 1.0, y: this.isPressedScanCard ? 0.98 : 1.0 })
          .animation({ duration: 100, curve: Curve.EaseOut })
          .onTouch((event) => {
            if (event.type === TouchType.Down) {
              this.isPressedScanCard = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isPressedScanCard = false;
            }
          })
          .onClick(() => {
            this.startCameraScan();
          })

          // 模块二：手动粘贴与输入卡片
          Column({ space: 12 }) {
            Row() {
              Text('手动粘贴与解析')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
              
              Blank()
              
              Row({ space: 8 }) {
                Button('粘贴')
                  .fontSize(12)
                  .fontColor('#374151')
                  .backgroundColor('#E5E7EB')
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .borderRadius(6)
                  .onClick(() => {
                    this.pasteFromClipboard();
                  })

                if (this.importBuffer.length > 0) {
                  Button('清空')
                    .fontSize(12)
                    .fontColor('#EF4444')
                    .backgroundColor('#FEE2E2')
                    .height(28)
                    .padding({ left: 10, right: 10 })
                    .borderRadius(6)
                    .onClick(() => {
                      this.importBuffer = '';
                      this.lastError = '';
                    })
                }
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            TextArea({
              placeholder: this.t('placeholder.scannerPayload'),
              text: this.importBuffer
            })
              .height(160)
              .fontSize(13)
              .fontColor('#111827')
              .backgroundColor('#F9FAFB')
              .borderRadius(10)
              .padding(12)
              .onChange((value: string) => {
                this.importBuffer = value;
              })

            Text('支持粘贴 vmess://、vless://、ss://、trojan://、hysteria2:// 等协议链接，或 http://、https:// 订阅地址。')
              .fontSize(11)
              .fontColor('#9CA3AF')
              .width('100%')
              .lineHeight(16)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 })

          // 模块三：错误提示卡片
          if (this.lastError.length > 0) {
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Column()
                  .width(6)
                  .height(6)
                  .borderRadius(3)
                  .backgroundColor('#EF4444')
                
                Text('导入解析失败')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#B91C1C')
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Text(this.lastError)
                .fontSize(12)
                .fontColor('#991B1B')
                .width('100%')
                .lineHeight(16)
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#FEF2F2')
            .borderRadius(12)
            .borderWidth(1)
            .borderColor('#FCA5A5')
          }

          // 模块四：解析导入按钮
          Button() {
            Row() {
              if (this.isBusy) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color('#FFFFFF')
                  .margin({ right: 8 })
              }
              Text(this.t('action.importResult'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isImportEnabled() ? '#FFFFFF' : '#9CA3AF')
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(12)
          .enabled(this.isImportEnabled())
          .opacity(this.isImportEnabled() ? 1.0 : 0.65)
          .linearGradient(this.isImportEnabled() ? {
            angle: 90,
            colors: [['#FF8F3D', 0.0], ['#F97910', 1.0]]
          } : {
            angle: 90,
            colors: [['#E5E7EB', 0.0], ['#E5E7EB', 1.0]]
          })
          .scale({ x: this.isPressedImportBtn ? 0.97 : 1.0, y: this.isPressedImportBtn ? 0.97 : 1.0 })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onTouch((event) => {
            if (event.type === TouchType.Down) {
              this.isPressedImportBtn = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isPressedImportBtn = false;
            }
          })
          .onClick(() => {
            this.importResult();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F3F4F6')
  }

  private isImportEnabled(): boolean {
    return this.importBuffer.trim().length > 0 && !this.isBusy;
  }

  private async loadState(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.language = (await SETTINGS_CONTROLLER.load(context)).language;
      this.selectedNodeId = (await NODES_CONTROLLER.load(context, this.language)).selectedNodeId;
    } catch (error) {
      this.lastError = '加载配置状态失败: ' + JSON.stringify(error);
    }
  }

  private async startCameraScan(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };

      const result = await scanBarcode.startScanForResult(context, options);
      if (result && result.originalValue) {
        this.importBuffer = result.originalValue;
        this.lastError = '';
        // 扫码成功后，直接静默触发解析与导入
        await this.importResult();
      }
    } catch (error) {
      const err = error as Record<string, Object>;
      console.error('Scan barcode failed or cancelled:', JSON.stringify(error));
      // 20001 通常表示用户主动取消扫码面板
      if (err.code !== 20001 && err.code !== '20001') {
        this.lastError = '扫码失败: ' + (err.message || JSON.stringify(error));
      }
    }
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (systemPasteboard.hasDataSync()) {
        const pasteData = await systemPasteboard.getData();
        const text = pasteData.getPrimaryText();
        if (text && text.trim().length > 0) {
          this.importBuffer = text.trim();
          this.lastError = '';
          promptAction.showToast({ message: '已从剪贴板粘贴配置' });
        } else {
          promptAction.showToast({ message: '剪贴板内未发现有效文本' });
        }
      } else {
        promptAction.showToast({ message: '剪贴板为空' });
      }
    } catch (error) {
      promptAction.showToast({ message: '无法读取剪贴板内容' });
    }
  }

  private async importResult(): Promise<void> {
    const value = this.importBuffer.trim();
    if (value.length === 0) {
      this.lastError = this.t('error.emptyImport');
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
      return;
    }

    this.isBusy = true;
    this.lastError = '';
    try {
      const context = getContext(this) as common.Context;
      // 判定是否是订阅地址
      if (value.toLowerCase().startsWith('http://') || value.toLowerCase().startsWith('https://')) {
        const state = await SUBSCRIPTIONS_CONTROLLER.update(context, '', value, this.selectedNodeId, this.language);
        SHARED_RUNTIME_CONTROLLER.appendLog(state.subscriptionMessage);
        promptAction.showToast({ message: '订阅更新成功' });
        router.pushUrl({ url: AppRoute.SUBSCRIPTIONS });
        return;
      }

      // 解析节点
      const saved = await NODES_CONTROLLER.saveProfile(context, value, this.language);
      if (saved.profile === null) {
        this.lastError = saved.lastError;
        SHARED_RUNTIME_CONTROLLER.appendLog(saved.lastError);
        return;
      }

      let nodeName = '扫码导入';
      try {
        const obj = JSON.parse(saved.profile.outboundJson) as Record<string, Object>;
        if (obj.tag && typeof obj.tag === 'string' && obj.tag.trim().length > 0) {
          nodeName = obj.tag.trim();
        }
      } catch (err) {
        // ignore
      }

      await SubscriptionStore.addManualNode(context, nodeName, saved.profile.outboundJson);
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.profileSaved'));
      promptAction.showToast({ message: '节点导入成功' });
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
