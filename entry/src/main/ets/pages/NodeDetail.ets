import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, AppSettings, ProxyNode, SubscriptionGroup } from '../core/Profile';
import { markRuntimeSettingsRestartNeeded } from '../core/SettingsChange';
import { formatOutboundJsonToShareLink } from '../core/ShareLinkParser';
import { buildNodeFullConfigModel, NodeFullConfigModel } from '../features/nodes/NodeOperations';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { shareText, TextShareResult } from '../services/SystemShare';
import { DEFAULT_APP_SETTINGS } from '../storage/SettingsStore';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { AppRoute } from '../shell/AppRoute';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

interface NodeDetailParams {
  nodeId?: string;
}

const EMPTY_NODE: ProxyNode = {
  id: '',
  name: '',
  protocol: '',
  outboundJson: '',
  sourceUrl: '',
  rawLink: '',
  updatedAt: 0,
  delayMs: -1,
  delayTestAt: 0,
  delayStatus: ''
};

@Entry
@Component
struct NodeDetailPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private nodeId: string = '';
  @State private node: ProxyNode = EMPTY_NODE;
  @State private selectedNodeId: string = '';
  @State private settings: AppSettings = DEFAULT_APP_SETTINGS;
  @State private subscriptionGroups: Array<SubscriptionGroup> = [];
  @State private lastError: string = '';
  @State private qrImage: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    this.loadState();
  }

  onPageShow(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('node.detail.title'),
        summary: this.node.name,
        showBack: true
      })
      Scroll() {
        Column({ space: Space.lg }) {

          // 节点信息组
          SectionHeader({ title: '节点信息' })
          Column() {
            this.InfoRow('名称', this.node.name.length > 0 ? this.node.name : this.t('node.detail.missing'))
            this.RowDivider()
            this.InfoRow('协议', this.node.protocol.length > 0 ? this.node.protocol.toUpperCase() : '—')
            this.RowDivider()
            this.InfoRow('来源', this.node.sourceUrl.length > 0 ? this.t('node.source.subscription') : this.t('node.source.manual'))
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 主操作：使用 / 当前
          Button(this.node.id === this.selectedNodeId ? this.t('action.current') : this.t('action.use'))
            .height(46)
            .width('100%')
            .enabled(this.node.id.length > 0 && !SHARED_RUNTIME_CONTROLLER.isBusy())
            .backgroundColor(this.node.id === this.selectedNodeId ? AppColor.success : AppColor.brand)
            .fontColor(AppColor.onBrand)
            .fontWeight(FontWeight.Medium)
            .borderRadius(Radius.pill)
            .margin({ left: Space.lg, right: Space.lg, top: Space.sm })
            .onClick(() => {
              this.selectNode();
            })

          if (this.canEditCustomJson()) {
            Button(this.t('node.detail.editJson'))
              .height(44)
              .width('100%')
              .enabled(this.node.id.length > 0 && !SHARED_RUNTIME_CONTROLLER.isBusy())
              .backgroundColor(AppColor.surfaceAlt)
              .fontColor(AppColor.textPrimary)
              .fontSize(FontSz.callout)
              .fontWeight(FontWeight.Medium)
              .borderRadius(Radius.pill)
              .margin({ left: Space.lg, right: Space.lg })
              .onClick(() => {
                this.openJsonEditor();
              })
          }

          if (this.canEditAdvancedOutbound()) {
            Button(this.t('node.detail.editAdvanced'))
              .height(44)
              .width('100%')
              .enabled(this.node.id.length > 0 && !SHARED_RUNTIME_CONTROLLER.isBusy())
              .backgroundColor(AppColor.surfaceAlt)
              .fontColor(AppColor.textPrimary)
              .fontSize(FontSz.callout)
              .fontWeight(FontWeight.Medium)
              .borderRadius(Radius.pill)
              .margin({ left: Space.lg, right: Space.lg })
              .onClick(() => {
                this.openAdvancedEditor();
              })
          }

          Button(this.t('node.detail.copyFullConfig'))
            .height(44)
            .width('100%')
            .enabled(this.node.id.length > 0)
            .backgroundColor(AppColor.surfaceAlt)
            .fontColor(AppColor.textPrimary)
            .fontSize(FontSz.callout)
            .fontWeight(FontWeight.Medium)
            .borderRadius(Radius.pill)
            .margin({ left: Space.lg, right: Space.lg })
            .onClick(() => {
              this.copyFullConfig();
            })

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

          // Outbound JSON
          SectionHeader({ title: this.t('node.detail.outbound') })
          Column() {
            TextArea({ text: this.node.outboundJson, placeholder: this.t('placeholder.outbound') })
              .height(280)
              .width('100%')
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.textPrimary)
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding(Space.lg)
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 原始链接
          if (this.node.rawLink.length > 0) {
            SectionHeader({ title: this.t('node.detail.rawLink') })
            Column() {
              TextArea({ text: this.node.rawLink, placeholder: '' })
                .height(120)
                .width('100%')
                .fontSize(FontSz.footnote)
                .fontColor(AppColor.textPrimary)
                .backgroundColor(Color.Transparent)
                .borderRadius(0)
                .padding(Space.lg)
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })
          }

          // 二维码分享
          if (this.qrImage !== undefined) {
            SectionHeader({ title: this.t('node.detail.qr') })
            Column({ space: Space.md }) {
              Image(this.qrImage)
                .width(220)
                .height(220)
                .objectFit(ImageFit.Contain)
                .backgroundColor(Color.White)
                .borderRadius(Radius.md)
              Text(this.t('node.detail.qr.hint'))
                .fontSize(FontSz.footnote)
                .fontColor(AppColor.textTertiary)
                .textAlign(TextAlign.Center)
              Row({ space: Space.md }) {
                Button(this.t('node.detail.copyLink'))
                  .height(40)
                  .layoutWeight(1)
                  .backgroundColor(AppColor.surfaceAlt)
                  .fontColor(AppColor.textPrimary)
                  .fontSize(FontSz.callout)
                  .borderRadius(Radius.pill)
                  .onClick(() => {
                    this.copyShareLink();
                  })
                Button(this.t('action.share'))
                  .height(40)
                  .layoutWeight(1)
                  .backgroundColor(AppColor.brand)
                  .fontColor(AppColor.onBrand)
                  .fontSize(FontSz.callout)
                  .borderRadius(Radius.pill)
                  .onClick(() => {
                    this.shareNodeLink();
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(Space.lg)
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })
            .alignItems(HorizontalAlign.Center)
          }

          // 删除（危险操作）
          Column() {
            Row() {
              Text(this.t('action.del'))
                .fontSize(FontSz.callout)
                .fontColor(AppColor.danger)
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .width('100%')
            .padding(Space.lg)
            .onClick(() => {
              this.removeNode();
            })
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg, top: Space.sm })
          .enabled(this.node.id.length > 0)
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

  @Builder
  private InfoRow(label: string, value: string) {
    Row({ space: Space.md }) {
      Text(label)
        .fontSize(FontSz.callout)
        .fontColor(AppColor.textSecondary)
      Blank()
      Text(value)
        .fontSize(FontSz.callout)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(Space.lg)
  }

  private async loadState(): Promise<void> {
    const params = router.getParams() as NodeDetailParams;
    if (params !== undefined && params.nodeId !== undefined) {
      this.nodeId = params.nodeId;
    }
    const context = getContext(this) as common.Context;
    this.settings = await SETTINGS_CONTROLLER.load(context);
    this.language = this.settings.language;
    const state = await NODES_CONTROLLER.load(context, this.language);
    this.selectedNodeId = state.selectedNodeId;
    this.subscriptionGroups = state.subscriptionGroups;
    const found = NODES_CONTROLLER.findNode(state.nodes, this.nodeId);
    this.node = found !== null ? found : EMPTY_NODE;
    await this.generateQr();
  }

  private nodeShareLink(): string {
    const raw = this.node.rawLink.trim();
    if (raw.length > 0) {
      return raw;
    }
    return formatOutboundJsonToShareLink(this.node.outboundJson, this.node.name);
  }

  private async generateQr(): Promise<void> {
    const content = this.nodeShareLink();
    if (content.length === 0) {
      this.qrImage = undefined;
      return;
    }
    try {
      const options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        height: 600,
        width: 600
      };
      this.qrImage = await generateBarcode.createBarcode(content, options);
    } catch (error) {
      this.qrImage = undefined;
      SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('error.qrGenerate', 'error', JSON.stringify(error)));
    }
  }

  private copyShareLink(): void {
    const content = this.nodeShareLink();
    if (content.length === 0) {
      return;
    }
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
      systemPasteboard.setDataSync(pasteData);
      promptAction.showToast({ message: this.t('prompt.copiedToClipboard') });
    } catch (error) {
      promptAction.showToast({ message: this.t('prompt.copiedToClipboard') });
    }
  }

  private copyFullConfig(): void {
    const result: NodeFullConfigModel = buildNodeFullConfigModel(this.node, this.settings, this.subscriptionGroups);
    if (!result.success || result.content.trim().length === 0) {
      const message = result.message.length > 0 ? result.message : this.t('node.detail.fullConfigEmpty');
      promptAction.showToast({ message: this.f1('node.detail.fullConfigFailed', 'error', message) });
      return;
    }

    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, result.content);
      systemPasteboard.setDataSync(pasteData);
      promptAction.showToast({ message: this.t('node.detail.fullConfigCopied') });
    } catch (error) {
      promptAction.showToast({ message: this.f1('node.detail.fullConfigFailed', 'error', JSON.stringify(error)) });
    }
  }

  private async shareNodeLink(): Promise<void> {
    const content = this.nodeShareLink();
    if (content.length === 0) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const result = await shareText(context, this.node.name, content);
    this.handleShareResult(result);
  }

  private handleShareResult(result: TextShareResult): void {
    if (result.systemShareStarted) {
      promptAction.showToast({ message: this.t('share.started') });
      return;
    }
    if (result.copiedToClipboard) {
      promptAction.showToast({ message: this.t('share.fallbackCopied') });
      return;
    }
    promptAction.showToast({ message: this.f1('share.failed', 'error', result.errorMessage) });
  }

  private async selectNode(): Promise<void> {
    if (this.node.id.length === 0) {
      return;
    }
    this.selectedNodeId = this.node.id;
    const context = getContext(this) as common.Context;
    const state = await NODES_CONTROLLER.selectNode(context, this.node, this.language);
    this.selectedNodeId = state.selectedNodeId;
    this.lastError = state.lastError;
    if (state.lastError.length === 0) {
      markRuntimeSettingsRestartNeeded();
    }
    SHARED_RUNTIME_CONTROLLER.appendLog(state.lastError.length > 0 ? state.lastError : this.f1('log.selectedNode', 'name', this.node.name));
  }

  private async removeNode(): Promise<void> {
    if (this.node.id.length === 0) {
      return;
    }
    const context = getContext(this) as common.Context;
    await NODES_CONTROLLER.removeNode(context, this.node.id, this.language);
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.nodeRemoved', 'name', this.node.name));
    router.back();
  }

  private canEditCustomJson(): boolean {
    return this.node.id.length > 0 &&
      this.node.sourceUrl.trim().length === 0 &&
      this.node.rawLink.trim().length === 0 &&
      ((this.node.configType ?? 'outbound') === 'full' || this.node.protocol === 'custom');
  }

  private canEditAdvancedOutbound(): boolean {
    const configType = this.node.configType ?? 'outbound';
    return this.node.id.length > 0 &&
      this.node.sourceUrl.trim().length === 0 &&
      this.node.rawLink.trim().length === 0 &&
      (configType === 'proxy-chain' || configType === 'policy-group');
  }

  private openJsonEditor(): void {
    router.pushUrl({
      url: AppRoute.JSON_IMPORT,
      params: {
        nodeId: this.node.id
      }
    });
  }

  private openAdvancedEditor(): void {
    router.pushUrl({
      url: AppRoute.ADVANCED_OUTBOUND,
      params: {
        nodeId: this.node.id,
        mode: this.node.configType ?? this.node.protocol
      }
    });
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
