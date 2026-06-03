import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { IconButton } from '../components/IconButton';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, AppSettings, ConnectionStatus, ProxyNode, RuntimeStats, SubscriptionGroup } from '../core/Profile';
import { DelayTester, DelayTestResult } from '../services/DelayTester';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { DEFAULT_APP_SETTINGS } from '../storage/SettingsStore';
import { filterNodes, findInvalidNodes, exportNodesText } from '../features/nodes/NodeOperations';
import { NODES_CONTROLLER, NodesControllerState, SaveProfileResult } from '../features/nodes/NodesController';
import { ServerNodeCard } from '../features/servers/ServerCard';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { RuntimeViewState, SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SUBSCRIPTIONS_CONTROLLER, SubscriptionsControllerState } from '../features/subscriptions/SubscriptionsController';
import { AppRoute } from '../shell/AppRoute';
import { formatOne, formatTwo, localizeCoreMessage } from '../utils/LocalizationPresenter';

const EMPTY_STATS: RuntimeStats = {
  uploadBytes: 0,
  downloadBytes: 0,
  xrayRunning: false,
  tun2SocksRunning: false,
  lastMessage: translate(DEFAULT_LANGUAGE, 'runtime.nativeBridgeNotQueried')
};

@Entry
@Component
struct Index {
  private timerId: number = -1;
  private currentSettings: AppSettings = DEFAULT_APP_SETTINGS;

  @State private showSideBar: boolean = false;
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private outboundJson: string = '';
  @State private validationMessage: string = translate(DEFAULT_LANGUAGE, 'validation.initial');
  @State private validationOk: boolean = false;
  @State private lastError: string = '';
  @State private profileUpdatedAt: string = translate(DEFAULT_LANGUAGE, 'profile.notSaved');
  @State private profileUpdatedAtValue: number = 0;
  @State private subscriptionUrl: string = '';
  @State private nodes: Array<ProxyNode> = [];
  @State private selectedNodeId: string = '';
  @State private subscriptionMessage: string = translate(DEFAULT_LANGUAGE, 'subscription.none');
  @State private subscriptionUpdatedAt: number = 0;
  @State private subscriptionGroups: Array<SubscriptionGroup> = [];
  @State private selectedGroupId: string = '';
  @State private searchQuery: string = '';
  @State private subscriptionUpdating: boolean = false;
  @State private delayTesting: boolean = false;
  @State private status: ConnectionStatus = ConnectionStatus.IDLE;
  @State private connectionOperationRunning: boolean = false;
  @State private elapsedText: string = '00:00';
  @State private stats: RuntimeStats = EMPTY_STATS;

  aboutToAppear(): void {
    this.loadInitialState();
    if (this.timerId < 0) {
      this.timerId = setInterval(() => {
        this.refreshRuntime();
      }, 1000);
    }
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.HomeHeader()
        
        // 仪表盘卡片
        this.DashboardCard()

        if (this.lastError.length > 0) {
          Text(this.lastError)
            .fontSize(13)
            .fontColor('#B42318')
            .width('100%')
            .padding({ left: 24, right: 24, top: 12, bottom: 12 })
            .backgroundColor('#FEF3F2')
        }

        // 仅在有订阅分组时才显示 Tab 选项卡
        if (this.subscriptionGroups.length > 0) {
          this.GroupTabs()
        }

        Scroll() {
          this.NodeList()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .height('100%')
      .width('100%')
      .backgroundColor('#F6F8FA')

      if (this.showSideBar) {
        Column() {}
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .transition({ opacity: 0 })
          .onClick(() => {
            animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
              this.showSideBar = false;
            })
          })
      }

      Column() {
        this.DrawerContent()
      }
      .width(280)
      .height('100%')
      .backgroundColor('#FFFFFF')
      .position({ x: 0, y: 0 })
      .translate({ x: this.showSideBar ? 0 : -280 })
      .animation({ duration: 250, curve: Curve.EaseOut })
      .shadow({ radius: 12, color: '#33000000' })
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private HomeHeader() {
    Row({ space: 18 }) {
      IconButton({
        icon: $r('app.media.ic_menu'),
        buttonSize: 56,
        iconSize: 32,
        iconColor: '#49454F',
        onAction: () => {
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
            this.showSideBar = true;
          })
        }
      })

      Text(this.t('screen.servers.title'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1C1B1F')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column() {
        Image($r('app.media.ic_more_vert'))
          .width(30)
          .height(30)
          .fillColor('#49454F')
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(28)
      .bindMenu(this.MoreMenuBuilder())
    }
    .width('100%')
    .height(92)
    .padding({ left: 8, right: 10, top: 14 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private GroupTabs() {
    Column() {
      Row() {
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.subscriptionGroups, (group: SubscriptionGroup) => {
              this.GroupTab(group)
            }, (group: SubscriptionGroup, index: number) => `${index}-${group.id}`)
          }
          .padding({ left: 16, right: 16 })
          .height(44)
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)

        IconButton({
          icon: $r('app.media.ic_subscriptions'),
          buttonSize: 44,
          iconSize: 22,
          iconColor: '#4B5563',
          onAction: () => {
            this.openRoute(AppRoute.SUBSCRIPTIONS);
          }
        })
        .margin({ right: 16 })
      }
      .width('100%')
      .height(44)
      .margin({ top: 8, bottom: 8 })

      Divider()
        .strokeWidth(1)
        .color('#F3F4F6')
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private GroupTab(group: SubscriptionGroup) {
    Row() {
      Text(group.name.length > 0 ? group.name : 'Subscription')
        .fontSize(14)
        .fontWeight(group.id === this.selectedGroupId ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(group.id === this.selectedGroupId ? '#F97910' : '#4B5563')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(34)
    .padding({ left: 16, right: 16 })
    .borderRadius(17)
    .backgroundColor(group.id === this.selectedGroupId ? '#FFF7ED' : '#F3F4F6')
    .onClick(() => {
      this.selectSubscriptionGroup(group);
    })
  }

  @Builder
  private DashboardCard() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(this.statusLabel())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Text(this.isRunning() ? `已连接: ${this.elapsedText}` : '准备就绪')
            .fontSize(13)
            .fontColor('#6B7280')
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button() {
          Image(this.isRunning() ? $r('app.media.ic_stop') : $r('app.media.ic_play_arrow'))
            .width(26)
            .height(26)
            .fillColor('#FFFFFF')
        }
        .width(56)
        .height(56)
        .enabled(!this.isBusy())
        .backgroundColor(this.isRunning() ? '#F97910' : '#9CA3AF')
        .borderRadius(28)
        .shadow(this.isRunning() ? 
          { radius: 14, color: '#40F97910', offsetX: 0, offsetY: 6 } :
          { radius: 8, color: '#20000000', offsetX: 0, offsetY: 3 })
        .onClick(() => {
          if (this.isRunning()) {
            this.stopConnection();
          } else {
            this.startConnection();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .color('#F3F4F6')
        .strokeWidth(1)
        .margin({ top: 16, bottom: 16 })

      Row({ space: 16 }) {
        Row({ space: 10 }) {
          Column() {
            Image($r('app.media.ic_arrow_upward'))
              .width(14)
              .height(14)
              .fillColor('#F97910')
          }
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor('#FFF7ED')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Column({ space: 2 }) {
            Text(this.language === 'zh' ? '本次上传' : 'Upload')
              .fontSize(11)
              .fontColor('#9CA3AF')
            Text(this.formatBytes(this.stats.uploadBytes))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#374151')
          }
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)

        Row({ space: 10 }) {
          Column() {
            Image($r('app.media.ic_arrow_downward'))
              .width(14)
              .height(14)
              .fillColor('#10B981')
          }
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor('#ECFDF5')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Column({ space: 2 }) {
            Text(this.language === 'zh' ? '本次下载' : 'Download')
              .fontSize(11)
              .fontColor('#9CA3AF')
            Text(this.formatBytes(this.stats.downloadBytes))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#374151')
          }
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .padding(18)
    .margin({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .shadow({ radius: 8, color: '#08000000', offsetX: 0, offsetY: 3 })
  }

  private formatBytes(bytes: number): string {
    if (bytes === 0) {
      return '0 B';
    }
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
  }

  @Builder
  private NodeList() {
    Column({ space: 0 }) {
      if (this.subscriptionGroups.length === 0) {
        this.EmptyStateUI()
      } else if (this.visibleNodes().length === 0) {
        this.EmptyGroupNodesUI()
      } else {
        ForEach(this.visibleNodes(), (node: ProxyNode) => {
          ServerNodeCard({
            node,
            isSelected: node.id === this.selectedNodeId,
            isBusy: this.isBusy(),
            sourceLabel: this.nodeEndpointText(node),
            delayText: this.nodeDelayText(node),
            delayColor: this.nodeDelayColor(node),
            currentLabel: this.t('action.current'),
            useLabel: this.t('action.use'),
            openLabel: this.t('action.detail'),
            onSelect: (selectedNode: ProxyNode) => {
              this.selectNode(selectedNode);
            },
            onShare: (sharedNode: ProxyNode) => {
              this.shareNode(sharedNode);
            },
            onOpen: (openedNode: ProxyNode) => {
              this.openNodeDetail(openedNode);
            },
            onDelete: (deletedNode: ProxyNode) => {
              this.removeNode(deletedNode);
            }
          })
        }, (node: ProxyNode, index: number) => `${index}-${node.id}`)
      }
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private EmptyStateUI() {
    Column({ space: 24 }) {
      Column({ space: 12 }) {
        Image($r('app.media.ic_subscriptions'))
          .width(80)
          .height(80)
          .fillColor('#E5E7EB')
        
        Text('探索 Hey VPN')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2937')
          .margin({ top: 8 })

        Text('开启安全、自由的网络连接。请先添加订阅分组以同步您的服务器节点。')
          .fontSize(14)
          .fontColor('#9CA3AF')
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
          .lineHeight(20)
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')

      Column({ space: 12 }) {
        Button('添加订阅分组')
          .width(200)
          .height(44)
          .backgroundColor('#F97910')
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .borderRadius(22)
          .shadow({ radius: 8, color: '#30F97910', offsetX: 0, offsetY: 4 })
          .onClick(() => {
            this.openRoute(AppRoute.SUBSCRIPTIONS);
          })

        Button('手动配置 / 扫码导入')
          .width(200)
          .height(44)
          .backgroundColor('#F3F4F6')
          .fontColor('#4B5563')
          .fontWeight(FontWeight.Medium)
          .borderRadius(22)
          .onClick(() => {
            this.openRoute(AppRoute.IMPORT);
          })
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  @Builder
  private EmptyGroupNodesUI() {
    Column({ space: 20 }) {
      Image($r('app.media.ic_cloud_download'))
        .width(72)
        .height(72)
        .fillColor('#E5E7EB')

      Text('当前分组暂无节点')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4B5563')

      Text('您可以尝试手动更新当前订阅以同步最新的节点列表。')
        .fontSize(13)
        .fontColor('#9CA3AF')
        .textAlign(TextAlign.Center)
        .padding({ left: 40, right: 40 })

      Button('更新当前订阅')
        .height(38)
        .padding({ left: 24, right: 24 })
        .backgroundColor('#F97910')
        .fontColor('#FFFFFF')
        .borderRadius(19)
        .onClick(() => {
          this.updateSubscription();
        })
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  private async loadInitialState(): Promise<void> {
    await this.loadSettings();
    await this.loadNodes();
    await this.refreshRuntime();
  }

  private async loadSettings(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.currentSettings = await SETTINGS_CONTROLLER.load(context);
      this.language = this.currentSettings.language;
    } catch (error) {
      this.lastError = this.f1('error.loadSettings', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    }
  }

  private async loadNodes(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.applyNodesState(await NODES_CONTROLLER.load(context, this.language));
    } catch (error) {
      this.lastError = this.f1('error.loadSubscription', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    }
  }

  private async startConnection(): Promise<void> {
    if (this.isBusy()) {
      promptAction.showToast({ message: this.t('home.busy') });
      return;
    }

    this.connectionOperationRunning = true;
    try {
      await this.startConnectionInternal();
    } finally {
      this.connectionOperationRunning = false;
    }
  }

  private async startConnectionInternal(): Promise<boolean> {
    const context = getContext(this) as common.Context;
    const saved = await NODES_CONTROLLER.saveProfile(context, this.outboundJson, this.language);
    this.applySaveProfileResult(saved);
    if (saved.profile === null) {
      SHARED_RUNTIME_CONTROLLER.appendLog(saved.lastError);
      return false;
    }

    try {
      this.status = ConnectionStatus.STARTING;
      const state = await SHARED_RUNTIME_CONTROLLER.start(context, saved.profile, this.currentSettings, this.language);
      this.applyRuntimeState(state);
      return state.status === ConnectionStatus.RUNNING;
    } catch (error) {
      this.status = ConnectionStatus.ERROR;
      this.lastError = this.f1('vpn.startFailed', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
      return false;
    }
  }

  private async stopConnection(): Promise<void> {
    if (this.isBusy()) {
      promptAction.showToast({ message: this.t('home.busy') });
      return;
    }

    this.connectionOperationRunning = true;
    try {
      await this.stopConnectionInternal();
    } finally {
      this.connectionOperationRunning = false;
    }
  }

  private async stopConnectionInternal(): Promise<boolean> {
    try {
      const context = getContext(this) as common.Context;
      this.status = ConnectionStatus.STOPPING;
      const state = await SHARED_RUNTIME_CONTROLLER.stop(context, this.language);
      this.applyRuntimeState(state);
      return state.status === ConnectionStatus.IDLE;
    } catch (error) {
      this.status = ConnectionStatus.ERROR;
      this.lastError = this.f1('vpn.stopFailed', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
      return false;
    }
  }

  private async updateSubscription(): Promise<void> {
    if (this.subscriptionUpdating) {
      return;
    }
    this.subscriptionUpdating = true;
    this.subscriptionMessage = this.t('log.updatingSubscription');
    SHARED_RUNTIME_CONTROLLER.appendLog(this.subscriptionMessage);
    try {
      const context = getContext(this) as common.Context;
      const state = await SUBSCRIPTIONS_CONTROLLER.update(context, this.selectedGroupId, this.subscriptionUrl, this.selectedNodeId, this.language);
      this.applySubscriptionsState(state);
      SHARED_RUNTIME_CONTROLLER.appendLog(state.subscriptionMessage);
      this.applyNodesState(await NODES_CONTROLLER.load(context, this.language));
    } finally {
      this.subscriptionUpdating = false;
    }
  }

  private async selectNode(node: ProxyNode): Promise<void> {
    if (this.isBusy()) {
      promptAction.showToast({ message: this.t('home.busy') });
      return;
    }
    const context = getContext(this) as common.Context;
    const shouldSwitchConnection = this.isRunning() && node.id !== this.selectedNodeId;
    this.selectedNodeId = node.id;
    this.outboundJson = node.outboundJson;

    if (shouldSwitchConnection) {
      this.connectionOperationRunning = true;
    }

    try {
      const state = await NODES_CONTROLLER.selectNode(context, node, this.language);
      this.applyNodesState(state);
      const message = state.lastError.length > 0 ? state.lastError : this.f1('log.selectedNode', 'name', node.name);
      SHARED_RUNTIME_CONTROLLER.appendLog(message);

      if (shouldSwitchConnection && state.lastError.length === 0) {
        SHARED_RUNTIME_CONTROLLER.appendLog('检测到服务运行中，准备切换节点并重新连接...');
        const stopped = await this.stopConnectionInternal();
        if (stopped) {
          await this.startConnectionInternal();
        }
      }
    } finally {
      if (shouldSwitchConnection) {
        this.connectionOperationRunning = false;
      }
    }
  }

  private async shareNode(node: ProxyNode): Promise<void> {
    await this.selectNode(node);
    this.openRoute(AppRoute.EXPORT);
  }

  private async removeNode(node: ProxyNode): Promise<void> {
    const context = getContext(this) as common.Context;
    const state = await NODES_CONTROLLER.removeNode(context, node.id, this.language);
    this.applyNodesState(state);
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.nodeRemoved', 'name', node.name));
  }

  private async selectSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    const context = getContext(this) as common.Context;
    const state = await SUBSCRIPTIONS_CONTROLLER.selectGroup(context, group, this.language);
    this.applySubscriptionsState(state);
    SHARED_RUNTIME_CONTROLLER.appendLog(state.subscriptionMessage);
  }

  private async dedupeNodes(): Promise<void> {
    const before = this.nodes.length;
    const context = getContext(this) as common.Context;
    this.applyNodesState(await NODES_CONTROLLER.dedupeActiveGroupNodes(context, this.language));
    const removed = Math.max(0, before - this.nodes.length);
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.nodesDeduped', 'count', removed.toString()));
  }

  private async removeInvalidNodes(): Promise<void> {
    const invalid = findInvalidNodes(this.nodes).length;
    const context = getContext(this) as common.Context;
    this.applyNodesState(await NODES_CONTROLLER.removeInvalidNodes(context, this.language));
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.invalidNodesRemoved', 'count', invalid.toString()));
  }

  private async testVisibleNodeDelay(): Promise<void> {
    if (this.delayTesting) {
      return;
    }
    const targets = this.visibleNodes();
    if (targets.length === 0) {
      return;
    }

    this.delayTesting = true;
    SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.delayQueued'));
    try {
      const context = getContext(this) as common.Context;
      for (let index = 0; index < targets.length; index++) {
        const node = targets[index];
        const startedAt = Date.now();
        this.markNodeDelay(node.id, -1, 'testing', startedAt);
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.delayTestingNode', 'name', node.name));
        const result: DelayTestResult = await this.measureNodeTcpDelay(node, 8000);
        const delayMs = result.ok ? result.delayMs : -1;
        const status = result.ok ? 'ok' : result.status;
        const subscription = await SubscriptionStore.saveNodeDelay(context, node.id, delayMs, status, Date.now());
        this.applySubscriptionsState({
          subscriptionUrl: subscription.url,
          nodes: subscription.nodes,
          selectedNodeId: subscription.selectedNodeId,
          subscriptionMessage: this.subscriptionMessage,
          subscriptionUpdatedAt: subscription.updatedAt,
          subscriptionGroups: subscription.groups,
          selectedGroupId: subscription.selectedGroupId
        });
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f2('log.delayResult', 'name', node.name, 'result', this.delayResultText(result)));
      }
    } catch (error) {
      this.lastError = this.f1('error.delayTest', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    } finally {
      this.delayTesting = false;
    }
  }

  private async measureNodeTcpDelay(node: ProxyNode, timeoutMs: number): Promise<DelayTestResult> {
    const address = this.findJsonString(node.outboundJson, 'address');
    const portText = this.findJsonNumber(node.outboundJson, 'port');
    const port = Number(portText);
    return DelayTester.measureTcp(address, port, timeoutMs);
  }

  private showRealConnectionTestUnavailable(): void {
    const message = this.t('prompt.nativeDelayUnavailable');
    promptAction.showToast({ message });
    SHARED_RUNTIME_CONTROLLER.appendLog(message);
  }

  private markNodeDelay(nodeId: string, delayMs: number, delayStatus: string, delayTestAt: number): void {
    const next = new Array<ProxyNode>();
    for (let index = 0; index < this.nodes.length; index++) {
      const node = this.nodes[index];
      if (node.id === nodeId) {
        next.push({
          id: node.id,
          name: node.name,
          protocol: node.protocol,
          outboundJson: node.outboundJson,
          sourceUrl: node.sourceUrl,
          rawLink: node.rawLink,
          updatedAt: node.updatedAt,
          delayMs,
          delayTestAt,
          delayStatus
        });
      } else {
        next.push(node);
      }
    }
    this.nodes = next;
  }

  private async refreshRuntime(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.applyRuntimeState(await SHARED_RUNTIME_CONTROLLER.refresh(context, this.language));
    } catch (error) {
      this.lastError = JSON.stringify(error);
    }
  }

  private applyNodesState(state: NodesControllerState): void {
    this.outboundJson = state.outboundJson;
    this.validationOk = state.validationOk;
    this.validationMessage = state.validationMessage;
    this.profileUpdatedAt = state.profileUpdatedAt;
    this.profileUpdatedAtValue = state.profileUpdatedAtValue;
    this.subscriptionUrl = state.subscriptionUrl;
    this.nodes = state.nodes;
    this.selectedNodeId = state.selectedNodeId;
    this.subscriptionMessage = state.subscriptionMessage;
    this.subscriptionUpdatedAt = state.subscriptionUpdatedAt;
    this.subscriptionGroups = state.subscriptionGroups;
    this.selectedGroupId = state.selectedGroupId;
    this.lastError = state.lastError;
  }

  private applySaveProfileResult(result: SaveProfileResult): void {
    this.outboundJson = result.outboundJson;
    this.validationOk = result.validationOk;
    this.validationMessage = result.validationMessage;
    if (result.profile !== null) {
      this.profileUpdatedAt = result.profileUpdatedAt;
      this.profileUpdatedAtValue = result.profileUpdatedAtValue;
    }
    this.lastError = result.lastError;
  }

  private applySubscriptionsState(state: SubscriptionsControllerState): void {
    this.subscriptionUrl = state.subscriptionUrl;
    this.nodes = state.nodes;
    this.selectedNodeId = state.selectedNodeId;
    this.subscriptionMessage = state.subscriptionMessage;
    this.subscriptionUpdatedAt = state.subscriptionUpdatedAt;
    this.subscriptionGroups = state.subscriptionGroups;
    this.selectedGroupId = state.selectedGroupId;
  }

  private applyRuntimeState(state: RuntimeViewState): void {
    this.status = state.status;
    this.elapsedText = state.elapsedText;
    this.stats = state.stats;
    this.lastError = state.lastError;
  }

  private visibleNodes(): Array<ProxyNode> {
    return filterNodes(this.nodes, this.searchQuery);
  }

  private bottomStatusText(): string {
    if (this.isBusy()) {
      return this.t('home.busy');
    }
    if (this.isRunning()) {
      return this.t('home.connectedTest');
    }
    return this.t('home.disconnected');
  }

  private nodeEndpointText(node: ProxyNode): string {
    const address = this.findJsonString(node.outboundJson, 'address');
    const port = this.findJsonNumber(node.outboundJson, 'port');
    if (address.length > 0 && port.length > 0) {
      return `${address}:${port}`;
    }
    return node.sourceUrl.length > 0 ? this.t('node.source.subscription') : this.t('node.source.manual');
  }

  private findJsonString(value: string, key: string): string {
    const start = this.findJsonPropertyValueStart(value, key);
    if (start < 0) {
      return '';
    }
    let contentStart = start;
    while (contentStart < value.length && this.isJsonWhitespace(value.charAt(contentStart))) {
      contentStart++;
    }
    if (contentStart >= value.length || value.charAt(contentStart) !== '"') {
      return '';
    }
    contentStart++;
    const contentEnd = value.indexOf('"', contentStart);
    if (contentEnd < contentStart) {
      return '';
    }
    return value.substring(contentStart, contentEnd);
  }

  private findJsonNumber(value: string, key: string): string {
    const start = this.findJsonPropertyValueStart(value, key);
    if (start < 0) {
      return '';
    }
    let contentStart = start;
    while (contentStart < value.length && this.isJsonWhitespace(value.charAt(contentStart))) {
      contentStart++;
    }
    let contentEnd = contentStart;
    while (contentEnd < value.length && this.isJsonNumberChar(value.charAt(contentEnd))) {
      contentEnd++;
    }
    if (contentEnd <= contentStart) {
      return '';
    }
    return value.substring(contentStart, contentEnd);
  }

  private findJsonPropertyValueStart(value: string, key: string): number {
    const property = `"${key}"`;
    const propertyStart = value.indexOf(property);
    if (propertyStart < 0) {
      return -1;
    }
    const colon = value.indexOf(':', propertyStart + property.length);
    return colon < 0 ? -1 : colon + 1;
  }

  private isJsonWhitespace(value: string): boolean {
    return value === ' ' || value === '\n' || value === '\r' || value === '\t';
  }

  private isJsonNumberChar(value: string): boolean {
    return value >= '0' && value <= '9';
  }

  private openRoute(route: AppRoute): void {
    router.pushUrl({ url: route });
  }

  private openNodeDetail(node: ProxyNode): void {
    router.pushUrl({
      url: AppRoute.NODE_DETAIL,
      params: {
        nodeId: node.id
      }
    });
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

  private delayResultText(result: DelayTestResult): string {
    if (result.ok) {
      return this.f1('node.delay.ms', 'value', result.delayMs.toString());
    }
    return `${this.t('node.delay.failed')} ${result.status}`;
  }

  private statusLabel(): string {
    return this.t('status.' + this.status);
  }

  private localizeCoreMessage(message: string): string {
    return localizeCoreMessage(this.language, message);
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }

  private f2(key: string, name1: string, value1: string, name2: string, value2: string): string {
    return formatTwo(this.language, key, name1, value1, name2, value2);
  }

  private isRunning(): boolean {
    return this.status === ConnectionStatus.RUNNING;
  }

  private isBusy(): boolean {
    return this.connectionOperationRunning || this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.STOPPING;
  }

  @Builder
  private MoreMenuBuilder() {
    Menu() {
      MenuItem({ content: this.t('menu.serviceRestart') })
        .onClick(() => {
          this.reconnectService();
        })
      MenuItem({ content: this.t('menu.deleteConfig') })
        .onClick(() => {
          this.deleteCurrentConfig();
        })
      MenuItem({ content: this.t('menu.deleteDuplicate') })
        .onClick(() => {
          this.dedupeNodes();
        })
      MenuItem({ content: this.t('menu.deleteInvalid') })
        .onClick(() => {
          this.removeInvalidNodes();
        })
      MenuItem({ content: this.t('menu.exportClipboard') })
        .onClick(() => {
          this.exportAllNodesToClipboard();
        })
      MenuItem({ content: this.t('menu.testTcping') })
        .onClick(() => {
          this.testVisibleNodeDelay();
        })
      MenuItem({ content: this.t('menu.testRealConnection') })
        .onClick(() => {
          this.showRealConnectionTestUnavailable();
        })
      MenuItem({ content: this.t('menu.locateSelected') })
        .onClick(() => {
          this.locateSelectedConfig();
        })
      MenuItem({ content: this.t('menu.updateSubscription') })
        .onClick(() => {
          this.updateSubscription();
        })
    }
  }

  private async reconnectService(): Promise<void> {
    if (this.isBusy()) {
      promptAction.showToast({ message: this.t('home.busy') });
      return;
    }

    this.connectionOperationRunning = true;
    try {
      if (this.isRunning()) {
        SHARED_RUNTIME_CONTROLLER.appendLog('正在重启服务...');
        const stopped = await this.stopConnectionInternal();
        if (stopped) {
          await this.startConnectionInternal();
        }
      } else {
        await this.startConnectionInternal();
      }
    } finally {
      this.connectionOperationRunning = false;
    }
  }

  private async deleteCurrentConfig(): Promise<void> {
    if (this.selectedNodeId.length === 0) {
      promptAction.showToast({ message: this.t('prompt.noNodeToDelete') });
      return;
    }
    let targetNode: ProxyNode | null = null;
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === this.selectedNodeId) {
        targetNode = this.nodes[i];
        break;
      }
    }
    if (targetNode !== null) {
      await this.removeNode(targetNode);
      promptAction.showToast({ message: '配置已删除' });
    }
  }

  private async exportAllNodesToClipboard(): Promise<void> {
    const targets = this.visibleNodes();
    if (targets.length === 0) {
      promptAction.showToast({ message: this.t('export.empty') });
      return;
    }
    const text = exportNodesText(targets);
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: this.t('prompt.copiedToClipboard') });
      SHARED_RUNTIME_CONTROLLER.appendLog(`已成功导出 ${targets.length} 个节点至剪贴板。`);
    } catch (error) {
      promptAction.showToast({ message: '导出剪贴板失败：' + JSON.stringify(error) });
      SHARED_RUNTIME_CONTROLLER.appendLog('导出剪贴板失败：' + JSON.stringify(error));
    }
  }

  private locateSelectedConfig(): void {
    if (this.selectedNodeId.length === 0) {
      promptAction.showToast({ message: '当前未选中任何配置' });
      return;
    }
    let foundNode: ProxyNode | null = null;
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === this.selectedNodeId) {
        foundNode = this.nodes[i];
        break;
      }
    }
    if (foundNode !== null) {
      const msg = this.f1('prompt.locatedNode', 'name', foundNode.name);
      promptAction.showToast({ message: msg });
      SHARED_RUNTIME_CONTROLLER.appendLog(msg);
    }
  }

  private findSelectedNodeName(): string {
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === this.selectedNodeId) {
        return this.nodes[i].name;
      }
    }
    return '未选择';
  }

  @Builder
  private DrawerContent() {
    Column() {
      Column({ space: 8 }) {
        Text('Hey VPN')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        
        Text(this.isRunning() ? '服务正在运行' : '服务未连接')
          .fontSize(14)
          .fontColor('#FFEBE0')

        if (this.selectedNodeId.length > 0) {
          Text('当前节点: ' + this.findSelectedNodeName())
            .fontSize(12)
            .fontColor('#FFEBE0')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 48, bottom: 24 })
      .linearGradient({
        angle: 135,
        colors: [['#FF8F3D', 0.0], ['#F97910', 1.0]]
      })

      Scroll() {
        Column({ space: 4 }) {
          this.DrawerMenuItem('首页节点', $r('app.media.ic_menu'), () => {
            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.showSideBar = false;
            })
          }, true)

          Divider().color('#F3F4F6').strokeWidth(1).margin({ top: 4, bottom: 4 })

          this.DrawerMenuItem('添加配置', $r('app.media.ic_add'), () => {
            this.clickDrawerItem(AppRoute.IMPORT);
          })
          
          this.DrawerMenuItem('订阅分组', $r('app.media.ic_subscriptions'), () => {
            this.clickDrawerItem(AppRoute.SUBSCRIPTIONS);
          })

          this.DrawerMenuItem('路由设置', $r('app.media.ic_route'), () => {
            this.clickDrawerItem(AppRoute.ROUTING);
          })

          this.DrawerMenuItem('分应用代理', $r('app.media.ic_apps'), () => {
            this.clickDrawerItem(AppRoute.PER_APP);
          })

          this.DrawerMenuItem('资源文件', $r('app.media.ic_folder'), () => {
            this.clickDrawerItem(AppRoute.ASSETS);
          })

          this.DrawerMenuItem('系统日志', $r('app.media.ic_info'), () => {
            this.clickDrawerItem(AppRoute.LOGS);
          })

          this.DrawerMenuItem('扫描二维码', $r('app.media.ic_qr_code'), () => {
            this.clickDrawerItem(AppRoute.SCANNER);
          })

          this.DrawerMenuItem('设置偏好', $r('app.media.ic_settings'), () => {
            this.clickDrawerItem(AppRoute.SETTINGS);
          })

          this.DrawerMenuItem('关于应用', $r('app.media.ic_info'), () => {
            this.clickDrawerItem(AppRoute.ABOUT);
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DrawerMenuItem(title: string, icon: Resource, onClick: () => void, isSelected: boolean = false) {
    Row({ space: 16 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(isSelected ? '#F97910' : '#49454F')
      Text(title)
        .fontSize(15)
        .fontWeight(isSelected ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(isSelected ? '#F97910' : '#1C1B1F')
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor(isSelected ? '#FFF7ED' : '#00000000')
    .onClick(() => {
      onClick();
    })
  }

  private clickDrawerItem(route: AppRoute) {
    animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.showSideBar = false;
    })
    this.openRoute(route);
  }
}
