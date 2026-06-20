import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { scanBarcode, scanCore, detectBarcode } from '@kit.ScanKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { resolveImportedNodeName } from '../core/ImportedNodeNames';
import { shouldExposeLocalHttpProxy } from '../core/LocalProxy';
import { AppLanguage } from '../core/Profile';
import { markRuntimeSettingsRestartNeeded } from '../core/SettingsChange';
import { LOCAL_HTTP_PROXY_PORT } from '../core/XrayConfig';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SUBSCRIPTIONS_CONTROLLER } from '../features/subscriptions/SubscriptionsController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { ensureReadPasteboardPermission } from '../utils/ClipboardPermission';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { convertNativeShareTextToOutbounds } from '../services/NativeShareConverter';
import { AppColor } from '../theme/Theme';

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
  @State private isPressedPhotoCard: boolean = false;
  @State private isPressedImportBtn: boolean = false;
  private subscriptionProxyPort: number = 0;
  private startScanImmediate: boolean = false;

  aboutToAppear(): void {
    this.loadState();
  }

  onPageShow(): void {
    this.tryStartImmediateScan();
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
                .fillColor(AppColor.brand)
                .margin({ right: 12 })

              Column() {
                Text(this.t('scanner.camera.title'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColor.textPrimary)
                Text(this.t('scanner.camera.detail'))
                  .fontSize(12)
                  .fontColor(AppColor.textSecondary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Image($r('app.media.ic_chevron_right'))
                .width(18)
                .height(18)
                .fillColor(AppColor.textTertiary)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(AppColor.surface)
          .borderRadius(16)
          .shadow({ radius: 8, color: AppColor.shadowCard, offsetX: 0, offsetY: 2 })
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

          // 模块二：从相册图片解码二维码
          Column({ space: 12 }) {
            Row() {
              Image($r('app.media.ic_folder'))
                .width(28)
                .height(28)
                .fillColor(AppColor.brand)
                .margin({ right: 12 })

              Column() {
                Text(this.t('scanner.photo.title'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColor.textPrimary)
                Text(this.t('scanner.photo.detail'))
                  .fontSize(12)
                  .fontColor(AppColor.textSecondary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Image($r('app.media.ic_chevron_right'))
                .width(18)
                .height(18)
                .fillColor(AppColor.textTertiary)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(AppColor.surface)
          .borderRadius(16)
          .shadow({ radius: 8, color: AppColor.shadowCard, offsetX: 0, offsetY: 2 })
          .scale({ x: this.isPressedPhotoCard ? 0.98 : 1.0, y: this.isPressedPhotoCard ? 0.98 : 1.0 })
          .animation({ duration: 100, curve: Curve.EaseOut })
          .onTouch((event) => {
            if (event.type === TouchType.Down) {
              this.isPressedPhotoCard = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isPressedPhotoCard = false;
            }
          })
          .onClick(() => {
            this.selectPhotoQr();
          })

          // 模块三：手动粘贴与输入卡片
          Column({ space: 12 }) {
            Row() {
              Text(this.t('scanner.manual.title'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColor.textPrimary)

              Blank()

              Row({ space: 8 }) {
                Button(this.t('action.paste'))
                  .fontSize(12)
                  .fontColor(AppColor.textSecondary)
                  .backgroundColor(AppColor.border)
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .borderRadius(6)
                  .onClick(() => {
                    this.pasteFromClipboard();
                  })

                if (this.importBuffer.length > 0) {
                  Button(this.t('action.clear'))
                    .fontSize(12)
                    .fontColor(AppColor.danger)
                    .backgroundColor(AppColor.dangerTint)
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
              .fontColor(AppColor.textPrimary)
              .backgroundColor(AppColor.surfaceAlt)
              .borderRadius(10)
              .padding(12)
              .onChange((value: string) => {
                this.importBuffer = value;
              })

            Text(this.t('scanner.supportedPayloads'))
              .fontSize(11)
              .fontColor(AppColor.textTertiary)
              .width('100%')
              .lineHeight(16)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(AppColor.surface)
          .borderRadius(16)
          .shadow({ radius: 8, color: AppColor.shadowCard, offsetX: 0, offsetY: 2 })

          // 模块四：错误提示卡片
          if (this.lastError.length > 0) {
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Column()
                  .width(6)
                  .height(6)
                  .borderRadius(3)
                  .backgroundColor(AppColor.danger)

                Text(this.t('scanner.importFailedTitle'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColor.danger)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Text(this.lastError)
                .fontSize(12)
                .fontColor(AppColor.danger)
                .width('100%')
                .lineHeight(16)
            }
            .width('100%')
            .padding(14)
            .backgroundColor(AppColor.dangerTint)
            .borderRadius(12)
            .borderWidth(1)
            .borderColor(AppColor.danger)
          }

          // 模块五：解析导入按钮
          Button() {
            Row() {
              if (this.isBusy) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColor.onBrand)
                  .margin({ right: 8 })
              }
              Text(this.t('action.importResult'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isImportEnabled() ? AppColor.onBrand : AppColor.textTertiary)
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(12)
          .enabled(this.isImportEnabled())
          .opacity(this.isImportEnabled() ? 1.0 : 0.65)
          .linearGradient(this.isImportEnabled() ? {
            angle: 90,
            colors: [[AppColor.brandStrong, 0.0], [AppColor.brand, 1.0]]
          } : {
            angle: 90,
            colors: [[AppColor.border, 0.0], [AppColor.border, 1.0]]
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
    .backgroundColor(AppColor.bg)
  }

  private isImportEnabled(): boolean {
    return this.importBuffer.trim().length > 0 && !this.isBusy;
  }

  private async loadState(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const settings = await SETTINGS_CONTROLLER.load(context);
      this.language = settings.language;
      this.startScanImmediate = settings.startScanImmediate;
      this.subscriptionProxyPort = shouldExposeLocalHttpProxy(settings) && SHARED_RUNTIME_CONTROLLER.isRunning() ?
        LOCAL_HTTP_PROXY_PORT : 0;
      this.selectedNodeId = (await NODES_CONTROLLER.load(context, this.language)).selectedNodeId;
      this.tryStartImmediateScan();
    } catch (error) {
      this.lastError = this.f1('scanner.loadStateFailed', 'error', JSON.stringify(error));
    }
  }

  private tryStartImmediateScan(): void {
    if (!this.startScanImmediate || this.hasAutoScanned) {
      return;
    }
    this.hasAutoScanned = true;
    // 延迟拉起扫码，确保转场动画完全结束后再加载扫码面板，体验更流畅。
    setTimeout(() => {
      this.startCameraScan();
    }, 300);
  }

  private async startCameraScan(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };

      const result = await scanBarcode.startScanForResult(context, options);
      await this.importScannedValue(result?.originalValue);
    } catch (error) {
      console.error('Scan barcode failed or cancelled:', JSON.stringify(error));
      if (!this.isUserCancelled(error)) {
        this.lastError = this.f1('scanner.scanFailed', 'error', this.errorMessage(error));
      }
    }
  }

  private async selectPhotoQr(): Promise<void> {
    try {
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select(photoSelectOptions);
      if (!result || !result.photoUris || result.photoUris.length === 0) {
        return;
      }

      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false
      };
      const results = await detectBarcode.decode({ uri: result.photoUris[0] }, options);
      await this.importScannedValue(this.firstScanValue(results), this.t('scanner.decodeFailed'));
    } catch (error) {
      console.error('Decode QR image failed or cancelled:', JSON.stringify(error));
      if (!this.isUserCancelled(error)) {
        this.lastError = this.f1('scanner.photoImportFailed', 'error', this.errorMessage(error));
      }
    }
  }

  private firstScanValue(results: Array<scanBarcode.ScanResult>): string {
    for (let index = 0; index < results.length; index++) {
      const value = results[index].originalValue;
      if (value && value.trim().length > 0) {
        return value;
      }
    }
    return '';
  }

  private async importScannedValue(value: string | undefined, emptyMessage?: string): Promise<void> {
    if (!value || value.trim().length === 0) {
      if (emptyMessage && emptyMessage.length > 0) {
        this.lastError = emptyMessage;
      }
      return;
    }
    this.importBuffer = value.trim();
    this.lastError = '';
    await this.importResult();
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      if (!await ensureReadPasteboardPermission(context)) {
        promptAction.showToast({ message: this.t('prompt.clipboardReadFailed') });
        return;
      }
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (systemPasteboard.hasDataSync()) {
        const pasteData = await systemPasteboard.getData();
        const text = pasteData.getPrimaryText();
        if (text && text.trim().length > 0) {
          this.importBuffer = text.trim();
          this.lastError = '';
          promptAction.showToast({ message: this.t('prompt.pastedConfig') });
        } else {
          promptAction.showToast({ message: this.t('prompt.clipboardTextEmpty') });
        }
      } else {
        promptAction.showToast({ message: this.t('prompt.clipboardNoData') });
      }
    } catch (error) {
      promptAction.showToast({ message: this.t('prompt.clipboardReadFailed') });
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
        const state = await SUBSCRIPTIONS_CONTROLLER.update(context, '', value, this.selectedNodeId, this.language, this.subscriptionProxyPort);
        SHARED_RUNTIME_CONTROLLER.appendLog(state.subscriptionMessage);
        promptAction.showToast({ message: this.t('scanner.subscriptionUpdated') });
        router.pushUrl({ url: AppRoute.SUBSCRIPTIONS });
        return;
      }

      // 解析节点
      const saved = await NODES_CONTROLLER.saveProfile(context, value, this.language);
      if (saved.profile === null) {
        const nativeResult = convertNativeShareTextToOutbounds(value);
        if (!nativeResult.ok) {
          this.lastError = nativeResult.message.length > 0 ? `${saved.lastError}\n${nativeResult.message}` : saved.lastError;
          SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
          return;
        }

        let importedCount = 0;
        let lastValidationError = '';
        for (let index = 0; index < nativeResult.outbounds.length; index++) {
          const outbound = nativeResult.outbounds[index];
          const imported = await NODES_CONTROLLER.saveProfile(context, outbound.outboundJson, this.language, 'outbound');
          if (imported.profile === null) {
            lastValidationError = imported.lastError;
            continue;
          }
          await SubscriptionStore.addManualNode(
            context,
            resolveImportedNodeName(imported.profile.outboundJson, outbound.name),
            imported.profile.outboundJson,
            imported.profile.configType
          );
          importedCount++;
        }

        if (importedCount === 0) {
          this.lastError = lastValidationError.length > 0 ? lastValidationError : saved.lastError;
          SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
          return;
        }

        markRuntimeSettingsRestartNeeded();
        const successMessage = importedCount === 1 ?
          this.t('scanner.nodeImported') : this.f1('scanner.nodesImported', 'count', importedCount.toString());
        SHARED_RUNTIME_CONTROLLER.appendLog(successMessage);
        promptAction.showToast({ message: successMessage });
        router.back();
        return;
      }

      const nodeName = resolveImportedNodeName(saved.profile.outboundJson, this.t('scanner.defaultNodeName'));
      await SubscriptionStore.addManualNode(context, nodeName, saved.profile.outboundJson, saved.profile.configType);
      markRuntimeSettingsRestartNeeded();
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.profileSaved'));
      promptAction.showToast({ message: this.t('scanner.nodeImported') });
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

  private isUserCancelled(error: Object): boolean {
    const record = error as Record<string, Object>;
    const code = record['code'];
    return code === 20001 || code === '20001' || code === 1000500002 || code === '1000500002';
  }

  private errorMessage(error: Object): string {
    const record = error as Record<string, Object>;
    const message = record['message'];
    if (typeof message === 'string' && message.length > 0) {
      return message;
    }
    return JSON.stringify(error);
  }
}
