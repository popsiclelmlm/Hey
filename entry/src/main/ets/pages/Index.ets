import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { IconButton } from '../components/IconButton';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, AppSettings, ConnectionStatus, normalizeRealPingConcurrency, ProxyNode, RuntimeStats, SubscriptionGroup } from '../core/Profile';
import { LOCAL_HTTP_PROXY_PORT } from '../core/XrayConfig';
import { DeepLinkIntent, parseDeepLink, subscriptionNameFromDeepLink } from '../core/DeepLink';
import { DelayTester, DelayTestResult } from '../services/DelayTester';
import { SubscriptionManager } from '../services/SubscriptionManager';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { DEFAULT_APP_SETTINGS } from '../storage/SettingsStore';
import { filterNodes, findInvalidNodes, exportNodesText, sortNodes, removeTestFailedNodesFromList } from '../features/nodes/NodeOperations';
import { NODES_CONTROLLER, NodesControllerState, SaveProfileResult } from '../features/nodes/NodesController';
import { ServerNodeCard } from '../features/servers/ServerCard';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { RuntimeViewState, SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SUBSCRIPTIONS_CONTROLLER, SubscriptionsControllerState } from '../features/subscriptions/SubscriptionsController';
import { AppRoute } from '../shell/AppRoute';
import { formatOne, formatTwo, localizeCoreMessage } from '../utils/LocalizationPresenter';
import { AppColor, Elevation, FontSz, Radius, Space } from '../theme/Theme';

const EMPTY_STATS: RuntimeStats = {
  uploadBytes: 0,
  downloadBytes: 0,
  xrayRunning: false,
  tunRunning: false,
  lastMessage: translate(DEFAULT_LANGUAGE, 'runtime.nativeBridgeNotQueried')
};
const AUTO_SUBSCRIPTION_CHECK_THROTTLE_MS: number = 60 * 1000;
const ALL_GROUP_ID: string = '__hey_all_groups__';

interface NodeDelayBatchResult {
  node: ProxyNode;
  result: DelayTestResult;
  testedAt: number;
}

@Entry
@Component
struct Index {
  private timerId: number = -1;
  private currentSettings: AppSettings = DEFAULT_APP_SETTINGS;
  private tabsController: TabsController = new TabsController();
  private lastAutoSubscriptionCheckAt: number = 0;

  @State private currentTab: number = 0;
  @State private showSearch: boolean = false;
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
  @State private speedEnabled: boolean = false;
  @State private groupAllDisplay: boolean = false;
  @State private allGroupsSelected: boolean = false;

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

  onPageShow(): void {
    // 从订阅 / 导入等子页返回时，重新加载设置与节点，保证列表实时刷新
    this.refreshFromStorage();
  }

  private async refreshFromStorage(): Promise<void> {
    await this.loadSettings();
    await this.loadNodes();
    await this.handlePendingDeepLink();
    await this.refreshDueSubscriptions();
  }

  // Imports a stashed deep link (hey://install-sub|install-config?url=...) once
  // when the page shows after EntryAbility received it. No-op on normal returns.
  private async handlePendingDeepLink(): Promise<void> {
    const link = AppStorage.get<string>('pendingDeepLink');
    if (link === undefined || link.length === 0) {
      return;
    }
    AppStorage.setOrCreate('pendingDeepLink', '');
    const intent: DeepLinkIntent = parseDeepLink(link);
    if (intent.kind === 'none') {
      return;
    }
    const context = getContext(this) as common.Context;
    try {
      if (intent.kind === 'sub') {
        const name = subscriptionNameFromDeepLink(intent.payload);
        const validationMessage = SubscriptionManager.validateSubscriptionUrl(intent.payload, false);
        if (validationMessage.length > 0) {
          this.lastError = localizeCoreMessage(this.language, validationMessage);
          SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
          return;
        }
        const added = await SUBSCRIPTIONS_CONTROLLER.addGroup(context, name, intent.payload, '', '', false, this.language);
        const state = await SUBSCRIPTIONS_CONTROLLER.update(context, added.selectedGroupId, intent.payload, '', this.language);
        this.applySubscriptionsState(state);
        this.applyNodesState(await NODES_CONTROLLER.load(context, this.language));
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.deepLinkSub', 'name', name));
      } else {
        const saved = await NODES_CONTROLLER.saveProfile(context, intent.payload, this.language);
        if (saved.profile === null) {
          this.lastError = saved.lastError;
          return;
        }
        const nodeName = this.nodeNameFromOutbound(saved.profile.outboundJson);
        await SubscriptionStore.addManualNode(context, nodeName, saved.profile.outboundJson, saved.profile.configType);
        this.applyNodesState(await NODES_CONTROLLER.load(context, this.language));
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.deepLinkConfig', 'name', nodeName));
      }
    } catch (error) {
      this.lastError = this.f1('error.deepLinkImport', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    }
  }

  private nodeNameFromOutbound(outboundJson: string): string {
    try {
      const obj = JSON.parse(outboundJson) as Record<string, Object>;
      const tag = obj.tag;
      if (typeof tag === 'string' && tag.trim().length > 0) {
        return tag.trim();
      }
      const remarks = obj.remarks;
      if (typeof remarks === 'string' && remarks.trim().length > 0) {
        return remarks.trim();
      }
      const name = obj.name;
      if (typeof name === 'string' && name.trim().length > 0) {
        return name.trim();
      }
    } catch (error) {
      // ignore and fall back
    }
    return '链接导入';
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab, controller: this.tabsController }) {
      TabContent() {
        this.ConnectTab()
      }
      .tabBar(this.TabBarItem(this.t('tab.connect'), $r('app.media.ic_shield'), 0))

      TabContent() {
        this.NodesTab()
      }
      .tabBar(this.TabBarItem(this.t('tab.nodes'), $r('app.media.ic_globe'), 1))

      TabContent() {
        this.SettingsTab()
      }
      .tabBar(this.TabBarItem(this.t('tab.settings'), $r('app.media.ic_settings'), 2))
    }
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .animationDuration(0)
    .divider({ strokeWidth: 0.5, color: AppColor.divider })
    .onChange((index: number) => {
      this.currentTab = index;
    })
    .backgroundColor(AppColor.bg)
    .width('100%')
    .height('100%')
  }

  @Builder
  private TabBarItem(label: string, icon: Resource, index: number) {
    Column({ space: 3 }) {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentTab === index ? AppColor.brand : AppColor.textTertiary)
      Text(label)
        .fontSize(FontSz.caption)
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentTab === index ? AppColor.brand : AppColor.textTertiary)
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ---------------------------------------------------------------------------
  // Tab 1 · 连接
  // ---------------------------------------------------------------------------

  @Builder
  private ConnectTab() {
    Column() {
      // 大标题
      Row() {
        Text('Hey')
          .fontSize(FontSz.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
      }
      .width('100%')
      .padding({ left: Space.xxl, right: Space.xxl, top: Space.xxl, bottom: Space.sm })

      if (this.lastError.length > 0) {
        Text(this.lastError)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.danger)
          .width('100%')
          .padding({ left: Space.xxl, right: Space.xxl, top: Space.sm, bottom: Space.sm })
          .backgroundColor(AppColor.dangerTint)
          .margin({ left: Space.lg, right: Space.lg })
          .borderRadius(Radius.md)
      }

      // 连接核心区（垂直居中）
      Column({ space: Space.xl }) {
        this.ConnectRing()

        Column({ space: Space.xs }) {
          Text(this.statusLabel())
            .fontSize(FontSz.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isRunning() ? AppColor.brand : AppColor.textPrimary)
          Text(this.isRunning() ? this.elapsedText : this.t('home.ready'))
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textSecondary)
        }
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 当前节点选择器
      this.NodeSelectorRow()

      // 流量 / 时长统计
      this.StatsCard()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private ConnectRing() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(168)
        .height(168)
        .fill(this.isRunning() ? AppColor.brandTint : AppColor.surfaceAlt)
        .opacity(this.isRunning() ? 1 : 0.6)

      Column() {
        if (this.isBusy()) {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(this.isRunning() ? AppColor.onBrand : AppColor.brand)
        } else {
          Image(this.isRunning() ? $r('app.media.ic_stop') : $r('app.media.ic_play_arrow'))
            .width(44)
            .height(44)
            .fillColor(this.isRunning() ? AppColor.onBrand : AppColor.brand)
        }
      }
      .width(120)
      .height(120)
      .borderRadius(60)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.isRunning() ? AppColor.brand : AppColor.surface)
      .border(this.isRunning() ? { width: 0 } : { width: 1, color: AppColor.border })
      .shadow(this.isRunning()
        ? { radius: Elevation.glow, color: AppColor.shadowBrand, offsetX: 0, offsetY: 8 }
        : { radius: Elevation.card, color: AppColor.shadowCard, offsetX: 0, offsetY: 4 })
      .onClick(() => {
        if (this.isBusy()) {
          return;
        }
        if (this.isRunning()) {
          this.stopConnection();
        } else {
          this.startConnection();
        }
      })
    }
  }

  @Builder
  private NodeSelectorRow() {
    Row({ space: Space.md }) {
      Column() {
        Image($r('app.media.ic_globe'))
          .width(20)
          .height(20)
          .fillColor(this.selectedNodeId.length > 0 ? AppColor.brand : AppColor.textTertiary)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.selectedNodeId.length > 0 ? AppColor.brandTint : AppColor.surfaceAlt)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 2 }) {
        Text(this.t('home.currentNode'))
          .fontSize(FontSz.caption)
          .fontColor(AppColor.textTertiary)
        Text(this.selectedNodeId.length > 0 ? this.findSelectedNodeName() : this.t('home.noNodeSelected'))
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor(AppColor.textTertiary)
    }
    .width('100%')
    .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.md })
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .margin({ left: Space.lg, right: Space.lg, bottom: Space.md })
    .onClick(() => {
      this.tabsController.changeIndex(1);
      this.currentTab = 1;
    })
  }

  @Builder
  private StatsCard() {
    Row() {
      this.StatCell(this.t('home.duration'), this.isRunning() ? this.elapsedText : '--', AppColor.textPrimary)
      if (this.speedEnabled) {
        Divider().vertical(true).height(28).color(AppColor.divider)
        this.StatCell(this.t('home.upload'), this.formatBytes(this.stats.uploadBytes), AppColor.brand)
        Divider().vertical(true).height(28).color(AppColor.divider)
        this.StatCell(this.t('home.download'), this.formatBytes(this.stats.downloadBytes), AppColor.success)
      }
    }
    .width('100%')
    .padding({ top: Space.md, bottom: Space.md })
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .margin({ left: Space.lg, right: Space.lg, bottom: Space.xl })
  }

  @Builder
  private StatCell(label: string, value: string, valueColor: ResourceColor) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(FontSz.callout)
        .fontWeight(FontWeight.Bold)
        .fontColor(valueColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(FontSz.caption)
        .fontColor(AppColor.textTertiary)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  // ---------------------------------------------------------------------------
  // Tab 2 · 节点
  // ---------------------------------------------------------------------------

  @Builder
  private NodesTab() {
    Column() {
      // 标题栏 / 搜索栏（就地切换）
      this.NodesHeader()

      if (this.subscriptionGroups.length > 0) {
        this.GroupTabs()
      }

      if (this.subscriptionGroups.length === 0) {
        Scroll() {
          this.EmptyStateUI()
        }
        .layoutWeight(1)
        .width('100%')
      } else if (this.visibleNodes().length === 0) {
        Scroll() {
          this.EmptyGroupNodesUI()
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        this.NodeList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private NodesHeader() {
    if (this.showSearch) {
      Row({ space: Space.sm }) {
        Search({ value: this.searchQuery, placeholder: this.t('nodes.searchPlaceholder') })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(AppColor.surfaceAlt)
          .placeholderColor(AppColor.textTertiary)
          .onChange((value: string) => {
            this.searchQuery = value;
          })

        Text(this.t('action.cancel'))
          .fontSize(FontSz.callout)
          .fontColor(AppColor.brand)
          .onClick(() => {
            animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
              this.showSearch = false;
              this.searchQuery = '';
            })
          })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.sm })
    } else {
      Row({ space: Space.xs }) {
        Text(this.t('tab.nodes'))
          .fontSize(FontSz.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
          .layoutWeight(1)

        IconButton({
          icon: $r('app.media.ic_search'),
          buttonSize: 44,
          iconSize: 24,
          iconColor: AppColor.textSecondary,
          onAction: () => {
            animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
              this.showSearch = true;
            })
          }
        })

        Column() {
          Image($r('app.media.ic_more_vert'))
            .width(24)
            .height(24)
            .fillColor(AppColor.textSecondary)
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .bindMenu(this.NodesMenu())
      }
      .width('100%')
      .padding({ left: Space.xxl, right: Space.lg, top: Space.xxl, bottom: Space.sm })
    }
  }

  @Builder
  private NodesMenu() {
    Menu() {
      MenuItem({ content: this.t('menu.updateSubscription') })
        .onClick(() => {
          this.updateSubscription();
        })
      MenuItem({ content: this.t('menu.testTcping') })
        .onClick(() => {
          this.testVisibleNodeDelay();
        })
      MenuItem({ content: this.t('menu.deleteConfig') })
        .onClick(() => {
          this.confirmClearNodes();
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
      MenuItem({ content: this.t('menu.serviceRestart') })
        .onClick(() => {
          this.reconnectService();
        })
      MenuItem({ content: this.t('menu.locateSelected') })
        .onClick(() => {
          this.locateSelectedConfig();
        })
    }
  }

  @Builder
  private GroupTabs() {
    Row() {
      Scroll() {
        Row({ space: Space.sm }) {
          ForEach(this.displaySubscriptionGroups(), (group: SubscriptionGroup) => {
            this.GroupTab(group)
          }, (group: SubscriptionGroup, index: number) => `${index}-${group.id}`)
        }
        .padding({ left: Space.lg, right: Space.lg })
        .height(40)
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height(48)
  }

  @Builder
  private GroupTab(group: SubscriptionGroup) {
    Row() {
      Text(group.name.length > 0 ? group.name : 'Subscription')
        .fontSize(FontSz.body)
        .fontWeight(this.isGroupTabSelected(group) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.isGroupTabSelected(group) ? AppColor.onBrand : AppColor.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(32)
    .padding({ left: Space.lg, right: Space.lg })
    .borderRadius(Radius.pill)
    .backgroundColor(this.isGroupTabSelected(group) ? AppColor.brand : AppColor.surfaceAlt)
    .onClick(() => {
      this.selectSubscriptionGroup(group);
    })
  }

  @Builder
  private NodeList() {
    List() {
      ForEach(this.visibleNodes(), (node: ProxyNode) => {
        ListItem() {
          ServerNodeCard({
            node,
            isSelected: node.id === this.selectedNodeId,
            sourceLabel: this.nodeEndpointText(node),
            delayText: this.nodeDelayText(node),
            delayColor: this.nodeDelayColor(node),
            onSelect: (selectedNode: ProxyNode) => {
              this.selectNode(selectedNode);
            }
          })
        }
        .swipeAction({ end: this.NodeSwipeActions(node) })
      }, (node: ProxyNode, index: number) => `${index}-${node.id}`)
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .divider({ strokeWidth: 0.5, color: AppColor.divider, startMargin: 56 })
    .scrollBar(BarState.Off)
    .margin({ left: Space.lg, right: Space.lg, top: Space.xs, bottom: Space.lg })
  }

  @Builder
  private NodeSwipeActions(node: ProxyNode) {
    Row() {
      this.SwipeButton($r('app.media.ic_share'), this.t('action.share'), AppColor.brand, () => {
        this.shareNode(node);
      })
      this.SwipeButton($r('app.media.ic_edit'), this.t('action.detail'), AppColor.textSecondary, () => {
        this.openNodeDetail(node);
      })
      this.SwipeButton($r('app.media.ic_delete'), this.t('action.delete'), AppColor.danger, () => {
        this.removeNode(node);
      })
    }
    .height('100%')
  }

  @Builder
  private SwipeButton(icon: Resource, label: string, bg: ResourceColor, action: () => void) {
    Column({ space: 3 }) {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(Color.White)
      Text(label)
        .fontSize(FontSz.caption)
        .fontColor(Color.White)
    }
    .width(72)
    .height('100%')
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      action();
    })
  }

  @Builder
  private EmptyStateUI() {
    Column({ space: Space.xxl }) {
      Column({ space: Space.md }) {
        Image($r('app.media.ic_subscriptions'))
          .width(72)
          .height(72)
          .fillColor(AppColor.textTertiary)
          .opacity(0.4)

        Text('探索 Hey VPN')
          .fontSize(FontSz.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
          .margin({ top: Space.sm })

        Text('开启安全、自由的网络连接。请先添加订阅分组以同步您的服务器节点。')
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .textAlign(TextAlign.Center)
          .padding({ left: Space.xxxl, right: Space.xxxl })
          .lineHeight(20)
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')

      Column({ space: Space.md }) {
        Button('添加订阅分组')
          .width(200)
          .height(44)
          .backgroundColor(AppColor.brand)
          .fontColor(AppColor.onBrand)
          .fontWeight(FontWeight.Medium)
          .borderRadius(Radius.pill)
          .onClick(() => {
            this.openRoute(AppRoute.SUBSCRIPTIONS);
          })

        Button('手动配置 / 扫码导入')
          .width(200)
          .height(44)
          .backgroundColor(AppColor.surfaceAlt)
          .fontColor(AppColor.textSecondary)
          .fontWeight(FontWeight.Medium)
          .borderRadius(Radius.pill)
          .onClick(() => {
            this.openRoute(AppRoute.IMPORT);
          })
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ top: 72, bottom: 72 })
  }

  @Builder
  private EmptyGroupNodesUI() {
    Column({ space: Space.xl }) {
      Image($r('app.media.ic_cloud_download'))
        .width(64)
        .height(64)
        .fillColor(AppColor.textTertiary)
        .opacity(0.4)

      Text('当前分组暂无节点')
        .fontSize(FontSz.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.textSecondary)

      Text('您可以尝试手动更新当前订阅以同步最新的节点列表。')
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textTertiary)
        .textAlign(TextAlign.Center)
        .padding({ left: 40, right: 40 })

      Button('更新当前订阅')
        .height(38)
        .padding({ left: Space.xxl, right: Space.xxl })
        .backgroundColor(AppColor.brand)
        .fontColor(AppColor.onBrand)
        .borderRadius(Radius.pill)
        .onClick(() => {
          this.updateSubscription();
        })
    }
    .width('100%')
    .padding({ top: 72, bottom: 72 })
  }

  // ---------------------------------------------------------------------------
  // Tab 3 · 设置
  // ---------------------------------------------------------------------------

  @Builder
  private SettingsTab() {
    Column() {
      Row() {
        Text(this.t('tab.settings'))
          .fontSize(FontSz.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
      }
      .width('100%')
      .padding({ left: Space.xxl, right: Space.xxl, top: Space.xxl, bottom: Space.sm })

      Scroll() {
        Column({ space: Space.lg }) {
          this.SettingsGroup(this.t('settings.group.nodes'), [
            new SettingsRowModel($r('app.media.ic_add'), this.t('screen.import.title'), AppRoute.IMPORT),
            new SettingsRowModel($r('app.media.ic_subscriptions'), this.t('screen.subscriptions.title'), AppRoute.SUBSCRIPTIONS),
            new SettingsRowModel($r('app.media.ic_qr_code'), this.t('screen.scanner.title'), AppRoute.SCANNER)
          ])

          this.SettingsGroup(this.t('settings.group.network'), [
            new SettingsRowModel($r('app.media.ic_route'), this.t('screen.routing.title'), AppRoute.ROUTING),
            new SettingsRowModel($r('app.media.ic_apps'), this.t('screen.perApp.title'), AppRoute.PER_APP),
            new SettingsRowModel($r('app.media.ic_folder'), this.t('screen.assets.title'), AppRoute.ASSETS)
          ])

          this.SettingsGroup(this.t('settings.group.general'), [
            new SettingsRowModel($r('app.media.ic_settings'), this.t('settings.row.preferences'), AppRoute.SETTINGS),
            new SettingsRowModel($r('app.media.ic_article'), this.t('screen.logs.title'), AppRoute.LOGS),
            new SettingsRowModel($r('app.media.ic_info'), this.t('screen.about.title'), AppRoute.ABOUT)
          ])
        }
        .width('100%')
        .padding({ bottom: Space.xxl })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private SettingsGroup(title: string, rows: Array<SettingsRowModel>) {
    Column({ space: 0 }) {
      Text(title)
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textTertiary)
        .width('100%')
        .padding({ left: Space.lg, bottom: Space.sm })

      Column({ space: 0 }) {
        ForEach(rows, (row: SettingsRowModel, index: number) => {
          this.SettingsRow(row, index === rows.length - 1)
        }, (row: SettingsRowModel, index: number) => `${index}-${row.title}`)
      }
      .width('100%')
      .backgroundColor(AppColor.surface)
      .borderRadius(Radius.lg)
      .clip(true)
    }
    .width('100%')
    .padding({ left: Space.lg, right: Space.lg })
  }

  @Builder
  private SettingsRow(row: SettingsRowModel, isLast: boolean) {
    Column() {
      Row({ space: Space.md }) {
        Image(row.icon)
          .width(22)
          .height(22)
          .fillColor(AppColor.textSecondary)

        Text(row.title)
          .fontSize(FontSz.callout)
          .fontColor(AppColor.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Image($r('app.media.ic_chevron_right'))
          .width(20)
          .height(20)
          .fillColor(AppColor.textTertiary)
      }
      .width('100%')
      .height(52)
      .padding({ left: Space.lg, right: Space.lg })

      if (!isLast) {
        Divider()
          .strokeWidth(0.5)
          .color(AppColor.divider)
          .margin({ left: 50 })
      }
    }
    .width('100%')
    .onClick(() => {
      this.openRoute(row.route);
    })
  }

  // ---------------------------------------------------------------------------
  // 逻辑（沿用既有实现）
  // ---------------------------------------------------------------------------

  private formatBytes(bytes: number): string {
    if (bytes === 0) {
      return '0 B';
    }
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
  }

  private async loadInitialState(): Promise<void> {
    await this.loadSettings();
    await this.loadNodes();
    await this.refreshDueSubscriptions();
    await this.refreshRuntime();
  }

  private async loadSettings(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.currentSettings = await SETTINGS_CONTROLLER.load(context);
      this.language = this.currentSettings.language;
      this.speedEnabled = this.currentSettings.speedEnabled;
      this.groupAllDisplay = this.currentSettings.groupAllDisplay;
      if (!this.groupAllDisplay) {
        this.allGroupsSelected = false;
      }
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

  private async refreshDueSubscriptions(): Promise<void> {
    const now = Date.now();
    if (now - this.lastAutoSubscriptionCheckAt < AUTO_SUBSCRIPTION_CHECK_THROTTLE_MS || this.subscriptionUpdating) {
      return;
    }

    this.lastAutoSubscriptionCheckAt = now;
    this.subscriptionUpdating = true;
    try {
      const context = getContext(this) as common.Context;
      const result = await SUBSCRIPTIONS_CONTROLLER.updateDue(context, this.language, now, this.subscriptionProxyPort());
      if (result.updatedCount === 0 && result.failedCount === 0) {
        return;
      }
      this.applySubscriptionsState(result.state);
      SHARED_RUNTIME_CONTROLLER.appendLog(result.state.subscriptionMessage);
      this.applyNodesState(await NODES_CONTROLLER.load(context, this.language));
    } catch (error) {
      this.lastError = this.f1('error.updateSubscription', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    } finally {
      this.subscriptionUpdating = false;
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
      const state = await SUBSCRIPTIONS_CONTROLLER.update(context, this.selectedGroupId, this.subscriptionUrl, this.selectedNodeId, this.language, this.subscriptionProxyPort());
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

  private removeNode(node: ProxyNode): void {
    if (this.currentSettings.confirmRemove) {
      AlertDialog.show({
        title: this.t('menu.deleteConfig'),
        message: this.f1('node.deleteConfirm', 'name', node.name),
        autoCancel: true,
        alignment: DialogAlignment.Bottom,
        offset: { dx: 0, dy: -20 },
        primaryButton: {
          value: this.t('action.delete'),
          fontColor: AppColor.onBrand,
          backgroundColor: AppColor.danger,
          action: () => {
            this.removeNodeImmediately(node);
          }
        },
        secondaryButton: {
          value: this.t('action.cancel'),
          fontColor: AppColor.textSecondary,
          backgroundColor: AppColor.bg,
          action: () => {}
        }
      });
      return;
    }
    this.removeNodeImmediately(node);
  }

  private async removeNodeImmediately(node: ProxyNode): Promise<void> {
    const context = getContext(this) as common.Context;
    const state = await NODES_CONTROLLER.removeNode(context, node.id, this.language);
    this.applyNodesState(state);
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.nodeRemoved', 'name', node.name));
  }

  private async selectSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    if (group.id === ALL_GROUP_ID) {
      this.allGroupsSelected = true;
      SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.openedSubscriptionGroup', 'name', group.name));
      return;
    }
    this.allGroupsSelected = false;
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

  private confirmClearNodes(): void {
    if (this.nodes.length === 0) {
      promptAction.showToast({ message: this.t('prompt.noNodesToDelete') });
      return;
    }
    AlertDialog.show({
      title: this.t('menu.deleteConfig'),
      message: this.t('node.deleteAllConfirm'),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: this.t('action.delete'),
        fontColor: AppColor.onBrand,
        backgroundColor: AppColor.danger,
        action: () => {
          this.clearActiveGroupNodes();
        }
      },
      secondaryButton: {
        value: this.t('action.cancel'),
        fontColor: AppColor.textSecondary,
        backgroundColor: AppColor.bg,
        action: () => {}
      }
    })
  }

  private async clearActiveGroupNodes(): Promise<void> {
    const removed = this.nodes.length;
    const context = getContext(this) as common.Context;
    this.applyNodesState(await NODES_CONTROLLER.clearActiveGroupNodes(context, this.language));
    const message = this.f1('log.nodesCleared', 'count', removed.toString());
    SHARED_RUNTIME_CONTROLLER.appendLog(message);
    promptAction.showToast({ message });
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
      const concurrency = normalizeRealPingConcurrency(this.currentSettings.realPingConcurrency);
      for (let start = 0; start < targets.length; start += concurrency) {
        const batch = targets.slice(start, Math.min(targets.length, start + concurrency));
        for (let index = 0; index < batch.length; index++) {
          const node = batch[index];
          const startedAt = Date.now();
          this.markNodeDelay(node.id, -1, 'testing', startedAt);
          SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.delayTestingNode', 'name', node.name));
        }

        const results = await this.measureNodeDelayBatch(batch);
        for (let index = 0; index < results.length; index++) {
          const item = results[index];
          const result = item.result;
          const delayMs = result.ok ? result.delayMs : -1;
          const status = result.ok ? 'ok' : result.status;
          const subscription = await SubscriptionStore.saveNodeDelay(context, item.node.id, delayMs, status, item.testedAt);
          this.applySubscriptionsState({
            subscriptionUrl: subscription.url,
            nodes: subscription.nodes,
            selectedNodeId: subscription.selectedNodeId,
            subscriptionMessage: this.subscriptionMessage,
            subscriptionUpdatedAt: subscription.updatedAt,
            subscriptionGroups: subscription.groups,
            selectedGroupId: subscription.selectedGroupId
          });
          SHARED_RUNTIME_CONTROLLER.appendLog(this.f2('log.delayResult', 'name', item.node.name, 'result', this.delayResultText(result)));
        }
      }
      await this.applyPostTestActions(context);
    } catch (error) {
      this.lastError = this.f1('error.delayTest', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    } finally {
      this.delayTesting = false;
    }
  }

  // After a batch delay test, optionally drop timed-out nodes and/or reorder by
  // latency, controlled by the auto-test settings. Persists the active group.
  private async applyPostTestActions(context: common.Context): Promise<void> {
    const autoRemove = this.currentSettings.autoRemoveInvalidAfterTest;
    const autoSort = this.currentSettings.autoSortAfterTest;
    if (!autoRemove && !autoSort) {
      return;
    }
    let processed: Array<ProxyNode> = this.nodes;
    if (autoRemove) {
      processed = removeTestFailedNodesFromList(processed);
    }
    if (autoSort) {
      processed = sortNodes(processed, 'delay');
    }
    const subscription = await SubscriptionStore.saveActiveGroupNodes(context, processed, this.selectedNodeId);
    this.applySubscriptionsState({
      subscriptionUrl: subscription.url,
      nodes: subscription.nodes,
      selectedNodeId: subscription.selectedNodeId,
      subscriptionMessage: this.subscriptionMessage,
      subscriptionUpdatedAt: subscription.updatedAt,
      subscriptionGroups: subscription.groups,
      selectedGroupId: subscription.selectedGroupId
    });
  }

  private async measureNodeTcpDelay(node: ProxyNode, timeoutMs: number): Promise<DelayTestResult> {
    const address = this.findJsonString(node.outboundJson, 'address');
    const portText = this.findJsonNumber(node.outboundJson, 'port');
    const port = Number(portText);
    return DelayTester.measureTcp(address, port, timeoutMs);
  }

  private async measureNodeDelayBatch(batch: Array<ProxyNode>): Promise<Array<NodeDelayBatchResult>> {
    const tasks = new Array<Promise<NodeDelayBatchResult>>();
    for (let index = 0; index < batch.length; index++) {
      tasks.push(this.measureNodeDelayForBatch(batch[index]));
    }
    return Promise.all(tasks);
  }

  private async measureNodeDelayForBatch(node: ProxyNode): Promise<NodeDelayBatchResult> {
    try {
      return {
        node,
        result: await this.measureNodeTcpDelay(node, 8000),
        testedAt: Date.now()
      };
    } catch (error) {
      return {
        node,
        result: {
          ok: false,
          delayMs: -1,
          status: JSON.stringify(error)
        },
        testedAt: Date.now()
      };
    }
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
          configType: node.configType,
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
    this.reconcileAllGroupsSelection();
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
    this.reconcileAllGroupsSelection();
  }

  private applyRuntimeState(state: RuntimeViewState): void {
    this.status = state.status;
    this.elapsedText = state.elapsedText;
    this.stats = state.stats;
    this.lastError = state.lastError;
  }

  private visibleNodes(): Array<ProxyNode> {
    return filterNodes(this.displayedNodes(), this.searchQuery);
  }

  private displayedNodes(): Array<ProxyNode> {
    if (!this.allGroupsSelected) {
      return this.nodes;
    }
    const result = new Array<ProxyNode>();
    for (let groupIndex = 0; groupIndex < this.subscriptionGroups.length; groupIndex++) {
      const group = this.subscriptionGroups[groupIndex];
      for (let nodeIndex = 0; nodeIndex < group.nodes.length; nodeIndex++) {
        result.push(group.nodes[nodeIndex]);
      }
    }
    return result;
  }

  private displaySubscriptionGroups(): Array<SubscriptionGroup> {
    if (!this.groupAllDisplay || this.subscriptionGroups.length === 0) {
      return this.subscriptionGroups;
    }
    const groups = new Array<SubscriptionGroup>();
    groups.push({
      id: ALL_GROUP_ID,
      name: this.t('nodes.groupAll'),
      url: '',
      enabled: true,
      selectedNodeId: '',
      nodes: [],
      updatedAt: 0
    });
    for (let index = 0; index < this.subscriptionGroups.length; index++) {
      groups.push(this.subscriptionGroups[index]);
    }
    return groups;
  }

  private isGroupTabSelected(group: SubscriptionGroup): boolean {
    if (group.id === ALL_GROUP_ID) {
      return this.allGroupsSelected;
    }
    return !this.allGroupsSelected && group.id === this.selectedGroupId;
  }

  private reconcileAllGroupsSelection(): void {
    if (!this.groupAllDisplay || this.subscriptionGroups.length === 0) {
      this.allGroupsSelected = false;
    }
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

  private nodeDelayColor(node: ProxyNode): ResourceColor {
    if (node.delayStatus === 'testing') {
      return AppColor.textSecondary;
    }
    if (node.delayMs >= 0) {
      if (node.delayMs <= 300) {
        return AppColor.success;
      }
      if (node.delayMs <= 900) {
        return AppColor.warning;
      }
    }
    if (node.delayStatus.length > 0) {
      return AppColor.danger;
    }
    return AppColor.textTertiary;
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

  private subscriptionProxyPort(): number {
    return this.isRunning() && this.currentSettings.appendHttpProxy ? LOCAL_HTTP_PROXY_PORT : 0;
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
    foundNode = this.findDisplayedNode(this.selectedNodeId);
    if (foundNode !== null) {
      const msg = this.f1('prompt.locatedNode', 'name', foundNode.name);
      promptAction.showToast({ message: msg });
      SHARED_RUNTIME_CONTROLLER.appendLog(msg);
    }
  }

  private findSelectedNodeName(): string {
    const node = this.findDisplayedNode(this.selectedNodeId);
    if (node !== null) {
      return node.name;
    }
    return this.t('home.noNodeSelected');
  }

  private findDisplayedNode(nodeId: string): ProxyNode | null {
    const nodes = this.displayedNodes();
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].id === nodeId) {
        return nodes[i];
      }
    }
    return null;
  }
}

class SettingsRowModel {
  icon: Resource;
  title: string;
  route: AppRoute;

  constructor(icon: Resource, title: string, route: AppRoute) {
    this.icon = icon;
    this.title = title;
    this.route = route;
  }
}
