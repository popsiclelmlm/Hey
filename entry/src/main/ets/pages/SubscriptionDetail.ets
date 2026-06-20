import { common } from '@kit.AbilityKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { shouldExposeLocalHttpProxy } from '../core/LocalProxy';
import { AppLanguage, ProxyNode, SubscriptionGroup } from '../core/Profile';
import { LOCAL_HTTP_PROXY_PORT } from '../core/XrayConfig';
import { NODES_CONTROLLER, NodesControllerState } from '../features/nodes/NodesController';
import { SubscriptionNodeRowModel } from '../features/subscriptions/SubscriptionPanel';
import { SubscriptionNodeListRow } from '../features/subscriptions/SubscriptionRows';
import { SUBSCRIPTIONS_CONTROLLER, SubscriptionsControllerState } from '../features/subscriptions/SubscriptionsController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { AppRoute } from '../shell/AppRoute';
import { SectionHeader } from '../components/SectionHeader';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { ensureReadPasteboardPermission } from '../utils/ClipboardPermission';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { shareText, TextShareResult } from '../services/SystemShare';

@Entry
@Component
struct SubscriptionDetailPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private groupId: string = '';
  @State private groupName: string = '订阅详情';
  @State private subscriptionUrl: string = '';
  @State private nodes: Array<ProxyNode> = [];
  @State private selectedNodeId: string = '';
  @State private subscriptionMessage: string = '';
  @State private isUpdating: boolean = false;
  @State private isBusy: boolean = false;
  @State private showSubscriptionQr: boolean = false;
  @State private subscriptionQrImage: image.PixelMap | undefined = undefined;

  // 状态卡片展示控制
  @State private showCard: boolean = false;
  @State private cardType: 'success' | 'error' | 'info' = 'info';
  private timerId: number = -1;
  private subscriptionProxyPort: number = 0;
  private subscriptionQrSource: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    this.groupId = (params?.groupId as string) ?? '';
    this.loadState();
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
  }

  build() {
    Column() {
      PageHeader({
        title: this.groupName,
        summary: `${this.nodes.length} 个节点`,
        showBack: true
      })

      Scroll() {
        Column({ space: Space.lg }) {
          // 订阅链接组
          SectionHeader({ title: '订阅链接' })
          Column() {
            Row() {
              Image($r('app.media.ic_link'))
                .width(20)
                .height(20)
                .fillColor(AppColor.textSecondary)
                .margin({ left: Space.lg, right: Space.sm })

              TextInput({
                placeholder: this.t('placeholder.subscriptionUrl'),
                text: this.subscriptionUrl
              })
                .layoutWeight(1)
                .height(48)
                .fontSize(FontSz.body)
                .fontColor(AppColor.textPrimary)
                .placeholderColor(AppColor.textTertiary)
                .backgroundColor(Color.Transparent)
                .onChange((value: string) => {
                  this.onSubscriptionUrlChanged(value);
                })

              if (this.subscriptionUrl.length > 0) {
                Button() {
                  Text('✕')
                    .fontSize(FontSz.body)
                    .fontColor(AppColor.textTertiary)
                    .fontWeight(FontWeight.Bold)
                }
                .backgroundColor(Color.Transparent)
                .width(36)
                .height(36)
                .onClick(() => {
                  this.subscriptionUrl = '';
                })
              }

              Button() {
                Image($r('app.media.ic_article'))
                  .width(20)
                  .height(20)
                  .fillColor(AppColor.textSecondary)
              }
              .backgroundColor(Color.Transparent)
              .width(36)
              .height(36)
              .onClick(() => {
                this.pasteFromClipboard();
              })

              Button() {
                Image($r('app.media.ic_qr_code'))
                  .width(20)
                  .height(20)
                  .fillColor(AppColor.textSecondary)
              }
              .backgroundColor(Color.Transparent)
              .width(36)
              .height(36)
              .margin({ right: Space.sm })
              .onClick(() => {
                router.pushUrl({ url: AppRoute.SCANNER });
              })

              if (this.subscriptionUrl.trim().length > 0) {
                Button() {
                  Image($r('app.media.ic_share'))
                    .width(20)
                    .height(20)
                    .fillColor(AppColor.textSecondary)
                }
                .backgroundColor(Color.Transparent)
                .width(36)
                .height(36)
                .margin({ right: Space.sm })
                .onClick(() => {
                  this.showSubscriptionQrPanel();
                })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          if (this.showSubscriptionQr && this.subscriptionUrl.trim().length > 0) {
            SectionHeader({ title: this.t('subscription.detail.qr') })
            Column({ space: Space.md }) {
              if (this.subscriptionQrImage !== undefined) {
                Image(this.subscriptionQrImage)
                  .width(220)
                  .height(220)
                  .objectFit(ImageFit.Contain)
                  .backgroundColor(Color.White)
                  .borderRadius(Radius.md)
              } else {
                LoadingProgress()
                  .width(48)
                  .height(48)
                  .color(AppColor.brand)
              }
              Text(this.t('subscription.detail.qr.hint'))
                .fontSize(FontSz.footnote)
                .fontColor(AppColor.textTertiary)
                .textAlign(TextAlign.Center)
              Row({ space: Space.md }) {
                Button(this.t('subscription.detail.copyLink'))
                  .height(40)
                  .layoutWeight(1)
                  .backgroundColor(AppColor.surfaceAlt)
                  .fontColor(AppColor.textPrimary)
                  .fontSize(FontSz.callout)
                  .borderRadius(Radius.pill)
                  .onClick(() => {
                    this.copySubscriptionLink();
                  })
                Button(this.t('action.share'))
                  .height(40)
                  .layoutWeight(1)
                  .backgroundColor(AppColor.brand)
                  .fontColor(AppColor.onBrand)
                  .fontSize(FontSz.callout)
                  .borderRadius(Radius.pill)
                  .onClick(() => {
                    this.shareSubscriptionLink();
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

          // 获取并更新按钮
          Button() {
            Row({ space: Space.sm }) {
              if (this.isUpdating) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColor.onBrand)
              }
              Text(this.isUpdating ? '正在获取并更新节点...' : '获取并更新节点')
                .fontSize(FontSz.callout)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isButtonEnabled() ? AppColor.onBrand : AppColor.textTertiary)
            }
          }
          .width('100%')
          .height(46)
          .borderRadius(Radius.pill)
          .enabled(this.isButtonEnabled())
          .backgroundColor(this.isButtonEnabled() ? AppColor.brand : AppColor.surfaceAlt)
          .margin({ left: Space.lg, right: Space.lg })
          .onClick(() => {
            this.updateSubscription();
          })

          // 成功/失败状态反馈卡片
          if (this.showCard) {
            Row({ space: Space.sm }) {
              Image(this.cardType === 'success' ? $r('app.media.ic_check') : $r('app.media.ic_info'))
                .width(18)
                .height(18)
                .fillColor(this.cardType === 'success' ? AppColor.success : this.cardType === 'error' ? AppColor.danger : AppColor.brand)

              Text(this.subscriptionMessage)
                .fontSize(FontSz.body)
                .fontColor(this.cardType === 'success' ? AppColor.success : this.cardType === 'error' ? AppColor.danger : AppColor.brand)
                .layoutWeight(1)

              Button() {
                Text('✕')
                  .fontSize(FontSz.footnote)
                  .fontColor(this.cardType === 'success' ? AppColor.success : this.cardType === 'error' ? AppColor.danger : AppColor.brand)
                  .fontWeight(FontWeight.Bold)
              }
              .backgroundColor(Color.Transparent)
              .width(28)
              .height(28)
              .onClick(() => {
                this.showCard = false;
              })
            }
            .width('100%')
            .padding({ left: Space.md, right: Space.sm, top: Space.md, bottom: Space.md })
            .borderRadius(Radius.md)
            .backgroundColor(this.cardType === 'success' ? AppColor.successTint : this.cardType === 'error' ? AppColor.dangerTint : AppColor.brandTint)
            .margin({ left: Space.lg, right: Space.lg })
          }

          // 节点列表组
          SectionHeader({ title: '节点列表' })
          if (this.nodes.length > 0) {
            Column() {
              ForEach(this.subscriptionNodeRows(), (row: SubscriptionNodeRowModel) => {
                SubscriptionNodeListRow({
                  node: row.node,
                  isSelected: row.isSelected,
                  isBusy: this.isBusy,
                  delayText: row.delayText,
                  delayColor: row.delayColor,
                  selectedLabel: this.t('action.selected'),
                  useLabel: this.t('action.use'),
                  onSelect: (node) => {
                    this.selectNode(node);
                  }
                })
              }, (row: SubscriptionNodeRowModel) => row.node.id)
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })
          } else {
            Column() {
              Text('此分组下暂无节点')
                .fontSize(FontSz.body)
                .fontColor(AppColor.textTertiary)
            }
            .width('100%')
            .height(160)
            .justifyContent(FlexAlign.Center)
          }
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

  private isButtonEnabled(): boolean {
    return this.subscriptionUrl.trim().length > 0 && !this.isUpdating && !this.isBusy;
  }

  private onSubscriptionUrlChanged(value: string): void {
    this.subscriptionUrl = value;
    if (value.trim() !== this.subscriptionQrSource) {
      this.showSubscriptionQr = false;
      this.subscriptionQrImage = undefined;
      this.subscriptionQrSource = '';
    }
  }

  private async showSubscriptionQrPanel(): Promise<void> {
    const url = this.subscriptionUrl.trim();
    if (url.length === 0) {
      return;
    }
    this.showSubscriptionQr = true;
    await this.generateSubscriptionQr(url);
  }

  private async generateSubscriptionQr(url: string): Promise<void> {
    if (this.subscriptionQrSource === url && this.subscriptionQrImage !== undefined) {
      return;
    }
    try {
      const options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        height: 600,
        width: 600
      };
      this.subscriptionQrImage = await generateBarcode.createBarcode(url, options);
      this.subscriptionQrSource = url;
    } catch (error) {
      this.subscriptionQrImage = undefined;
      this.subscriptionQrSource = '';
      this.showSubscriptionQr = false;
      const message = this.f1('error.qrGenerate', 'error', JSON.stringify(error));
      promptAction.showToast({ message });
      SHARED_RUNTIME_CONTROLLER.appendLog(message);
    }
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    const settings = await SETTINGS_CONTROLLER.load(context);
    this.language = settings.language;
    this.subscriptionProxyPort = shouldExposeLocalHttpProxy(settings) && SHARED_RUNTIME_CONTROLLER.isRunning() ?
      LOCAL_HTTP_PROXY_PORT : 0;
    let state = await SUBSCRIPTIONS_CONTROLLER.load(context, this.language);

    // 寻找对应的分组，激活它以加载节点
    let currentGroup: SubscriptionGroup | null = null;
    for (let i = 0; i < state.subscriptionGroups.length; i++) {
      if (state.subscriptionGroups[i].id === this.groupId) {
        currentGroup = state.subscriptionGroups[i];
        break;
      }
    }

    if (currentGroup !== null) {
      this.groupName = currentGroup.name;
      if (state.selectedGroupId !== this.groupId) {
        state = await SUBSCRIPTIONS_CONTROLLER.selectGroup(context, currentGroup, this.language);
      }
    }

    this.applySubscriptionsState(state);
  }

  private applySubscriptionsState(state: SubscriptionsControllerState): void {
    this.onSubscriptionUrlChanged(state.subscriptionUrl);
    this.nodes = state.nodes;
    this.selectedNodeId = state.selectedNodeId;
    this.subscriptionMessage = state.subscriptionMessage;

    // 更新消息通知卡片状态
    this.onMessageChange();
  }

  private async updateSubscription(): Promise<void> {
    if (this.isUpdating) {
      return;
    }
    this.isUpdating = true;
    this.subscriptionMessage = this.t('log.updatingSubscription');
    this.onMessageChange();

    try {
      const context = getContext(this) as common.Context;
      const state = await SUBSCRIPTIONS_CONTROLLER.update(context, this.groupId, this.subscriptionUrl, this.selectedNodeId, this.language, this.subscriptionProxyPort);
      this.applySubscriptionsState(state);
      SHARED_RUNTIME_CONTROLLER.appendLog(state.subscriptionMessage);
    } finally {
      this.isUpdating = false;
    }
  }

  private async selectNode(node: ProxyNode): Promise<void> {
    this.selectedNodeId = node.id;
    const context = getContext(this) as common.Context;
    const state: NodesControllerState = await NODES_CONTROLLER.selectNode(context, node, this.language);
    this.nodes = state.nodes;
    this.selectedNodeId = state.selectedNodeId;
    SHARED_RUNTIME_CONTROLLER.appendLog(state.lastError.length > 0 ? state.lastError : this.f1('log.selectedNode', 'name', node.name));
  }

  private onMessageChange() {
    if (!this.subscriptionMessage || this.subscriptionMessage.trim().length === 0) {
      this.showCard = false;
      return;
    }

    if (this.subscriptionMessage.includes('正在') || this.subscriptionMessage.includes('Updating') || this.subscriptionMessage.includes('updating')) {
      this.showCard = false;
      return;
    }

    this.showCard = true;
    if (this.subscriptionMessage.includes('失败') || this.subscriptionMessage.includes('Failed') || this.subscriptionMessage.includes('错误') || this.subscriptionMessage.includes('error')) {
      this.cardType = 'error';
    } else if (this.subscriptionMessage.includes('成功') || this.subscriptionMessage.includes('Success') || this.subscriptionMessage.includes('完成') || this.subscriptionMessage.includes('Complete') || this.subscriptionMessage.includes('保存')) {
      this.cardType = 'success';
    } else {
      this.cardType = 'info';
    }

    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
    this.timerId = setTimeout(() => {
      this.showCard = false;
      this.timerId = -1;
    }, 4000);
  }

  private async pasteFromClipboard() {
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
          this.subscriptionUrl = text.trim();
          promptAction.showToast({ message: this.t('prompt.pastedSubscriptionUrl') });
        } else {
          promptAction.showToast({ message: this.t('prompt.clipboardEmpty') });
        }
      } else {
        promptAction.showToast({ message: this.t('prompt.clipboardNoData') });
      }
    } catch (error) {
      promptAction.showToast({ message: this.t('prompt.clipboardReadFailed') });
    }
  }

  private copySubscriptionLink(): void {
    const url = this.subscriptionUrl.trim();
    if (url.length === 0) {
      return;
    }
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      systemPasteboard.setDataSync(pasteData);
      promptAction.showToast({ message: this.t('subscription.detail.copied') });
    } catch (error) {
      promptAction.showToast({ message: this.t('subscription.detail.copied') });
    }
  }

  private async shareSubscriptionLink(): Promise<void> {
    const url = this.subscriptionUrl.trim();
    if (url.length === 0) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const result = await shareText(context, this.groupName, url);
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

  private subscriptionNodeRows(): Array<SubscriptionNodeRowModel> {
    const rows: Array<SubscriptionNodeRowModel> = [];
    for (let index = 0; index < this.nodes.length; index++) {
      const node = this.nodes[index];
      rows.push({
        node,
        isSelected: node.id === this.selectedNodeId,
        delayText: this.nodeDelayText(node),
        delayColor: this.nodeDelayColor(node)
      });
    }
    return rows;
  }

  private nodeDelayText(node: ProxyNode): string {
    if (node.delayStatus === 'testing') {
      return this.t('node.delay.testing');
    }
    if (node.delayMs >= 0) {
      return this.f1('node.delay.ms', 'value', node.delayMs.toString());
    }
    if (node.delayStatus.length > 0) {
      return this.t('node.delay.failed');
    }
    return this.t('node.delay.pending');
  }

  private nodeDelayColor(node: ProxyNode): string {
    if (node.delayStatus === 'testing') {
      return '#F97910';
    }
    if (node.delayMs >= 0) {
      if (node.delayMs <= 300) {
        return '#166534';
      }
      if (node.delayMs <= 900) {
        return '#92400E';
      }
    }
    if (node.delayStatus.length > 0) {
      return '#B42318';
    }
    return '#6B7280';
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
