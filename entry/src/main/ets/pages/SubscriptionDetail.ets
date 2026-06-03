import { common } from '@kit.AbilityKit';
import { IconButton } from '../components/IconButton';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, ProxyNode, SubscriptionGroup } from '../core/Profile';
import { NODES_CONTROLLER, NodesControllerState } from '../features/nodes/NodesController';
import { SubscriptionNodeRowModel } from '../features/subscriptions/SubscriptionPanel';
import { SubscriptionNodeListRow } from '../features/subscriptions/SubscriptionRows';
import { SUBSCRIPTIONS_CONTROLLER, SubscriptionsControllerState } from '../features/subscriptions/SubscriptionsController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { formatOne, formatTwo } from '../utils/LocalizationPresenter';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

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

  // 状态卡片展示控制
  @State private showCard: boolean = false;
  @State private cardType: 'success' | 'error' | 'info' = 'info';
  private timerId: number = -1;

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
        Column({ space: 16 }) {
          // URL 编辑与操作面板
          Column({ space: 16 }) {
            // 输入行
            Row() {
              Image($r('app.media.ic_link'))
                .width(20)
                .height(20)
                .fillColor('#6B7280')
                .margin({ left: 12, right: 8 })

              TextInput({
                placeholder: this.t('placeholder.subscriptionUrl'),
                text: this.subscriptionUrl
              })
                .layoutWeight(1)
                .height(44)
                .fontSize(14)
                .fontColor('#111827')
                .placeholderColor('#9CA3AF')
                .backgroundColor('#00000000')
                .onChange((value: string) => {
                  this.subscriptionUrl = value;
                })

              if (this.subscriptionUrl.length > 0) {
                Button() {
                  Text('✕')
                    .fontSize(14)
                    .fontColor('#9CA3AF')
                    .fontWeight(FontWeight.Bold)
                }
                .backgroundColor('#00000000')
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
                  .fillColor('#6B7280')
              }
              .backgroundColor('#00000000')
              .width(36)
              .height(36)
              .onClick(() => {
                this.pasteFromClipboard();
              })

              Button() {
                Image($r('app.media.ic_qr_code'))
                  .width(20)
                  .height(20)
                  .fillColor('#6B7280')
              }
              .backgroundColor('#00000000')
              .width(36)
              .height(36)
              .margin({ right: 6 })
              .onClick(() => {
                router.pushUrl({ url: AppRoute.SCANNER });
              })
            }
            .width('100%')
            .height(48)
            .backgroundColor('#F9FAFB')
            .borderRadius(12)
            .border({ width: 1, color: '#E5E7EB' })
            .alignItems(VerticalAlign.Center)

            // 获取并更新按钮
            Button() {
              Row({ space: 8 }) {
                if (this.isUpdating) {
                  LoadingProgress()
                    .width(20)
                    .height(20)
                    .color('#FFFFFF')
                }
                Text(this.isUpdating ? '正在获取并更新节点...' : '获取并更新节点')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isButtonEnabled() ? '#FFFFFF' : '#9CA3AF')
              }
            }
            .width('100%')
            .height(44)
            .borderRadius(12)
            .enabled(this.isButtonEnabled())
            .opacity(this.isButtonEnabled() ? 1.0 : 0.65)
            .linearGradient(this.isButtonEnabled() ? {
              angle: 90,
              colors: [['#FF8F3D', 0.0], ['#F97910', 1.0]]
            } : {
              angle: 90,
              colors: [['#E5E7EB', 0.0], ['#E5E7EB', 1.0]]
            })
            .shadow(this.isButtonEnabled() ? { radius: 8, color: '#33F97910', offsetX: 0, offsetY: 4 } : undefined)
            .onClick(() => {
              this.updateSubscription();
            })

            // 成功/失败状态反馈卡片
            if (this.showCard) {
              Row({ space: 10 }) {
                Image(this.cardType === 'success' ? $r('app.media.ic_check') : $r('app.media.ic_info'))
                  .width(18)
                  .height(18)
                  .fillColor(this.cardType === 'success' ? '#2E7D32' : this.cardType === 'error' ? '#C62828' : '#1565C0')

                Text(this.subscriptionMessage)
                  .fontSize(13)
                  .fontColor(this.cardType === 'success' ? '#2E7D32' : this.cardType === 'error' ? '#C62828' : '#1565C0')
                  .layoutWeight(1)

                Button() {
                  Text('✕')
                    .fontSize(12)
                    .fontColor(this.cardType === 'success' ? '#2E7D32' : this.cardType === 'error' ? '#C62828' : '#1565C0')
                    .fontWeight(FontWeight.Bold)
                }
                .backgroundColor('#00000000')
                .width(28)
                .height(28)
                .onClick(() => {
                  this.showCard = false;
                })
              }
              .width('100%')
              .padding({ left: 12, right: 8, top: 10, bottom: 10 })
              .borderRadius(10)
              .backgroundColor(this.cardType === 'success' ? '#E8F5E9' : this.cardType === 'error' ? '#FFEBEE' : '#E3F2FD')
              .border({
                width: 1,
                color: this.cardType === 'success' ? '#A5D6A7' : this.cardType === 'error' ? '#EF9A9A' : '#90CAF9'
              })
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .shadow({ radius: 8, color: '#08000000', offsetX: 0, offsetY: 2 })

          // 节点列表卡片
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
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .shadow({ radius: 8, color: '#08000000', offsetX: 0, offsetY: 2 })
          } else {
            Column({ space: 12 }) {
              Text('此分组下暂无节点')
                .fontSize(14)
                .fontColor('#9CA3AF')
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F3F4F6')
  }

  private isButtonEnabled(): boolean {
    return this.subscriptionUrl.trim().length > 0 && !this.isUpdating && !this.isBusy;
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
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
    this.subscriptionUrl = state.subscriptionUrl;
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
      const state = await SUBSCRIPTIONS_CONTROLLER.update(context, this.subscriptionUrl, this.selectedNodeId, this.language);
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
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (systemPasteboard.hasDataSync()) {
        const pasteData = await systemPasteboard.getData();
        const text = pasteData.getPrimaryText();
        if (text && text.trim().length > 0) {
          this.subscriptionUrl = text.trim();
          promptAction.showToast({ message: '已粘贴订阅链接' });
        } else {
          promptAction.showToast({ message: '剪贴板未发现有效链接' });
        }
      } else {
        promptAction.showToast({ message: '剪贴板为空' });
      }
    } catch (error) {
      promptAction.showToast({ message: '无法读取剪贴板' });
    }
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
      return '#1D4ED8';
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
