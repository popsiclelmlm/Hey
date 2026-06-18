import { common } from '@kit.AbilityKit';
import { IconButton } from '../components/IconButton';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, SubscriptionGroup } from '../core/Profile';
import { LOCAL_HTTP_PROXY_PORT } from '../core/XrayConfig';
import { SUBSCRIPTIONS_CONTROLLER, SubscriptionsControllerState } from '../features/subscriptions/SubscriptionsController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

@Entry
@Component
struct SubscriptionsPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private subscriptionGroups: Array<SubscriptionGroup> = [];
  @State private selectedGroupId: string = '';
  @State private isUpdatingAll: boolean = false;
  @State private isBusy: boolean = false;
  private subscriptionProxyPort: number = 0;

  aboutToAppear(): void {
    this.loadState();
  }

  onPageShow(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.subscriptions.title'),
        summary: this.subscriptionGroups.length > 0 ? `共 ${this.subscriptionGroups.length} 个订阅分组` : '暂无订阅分组',
        showBack: true,
        rightActions: () => {
          this.HeaderActions()
        }
      })

      if (this.subscriptionGroups.length === 0) {
        Column({ space: Space.lg }) {
          Image($r('app.media.ic_subscriptions'))
            .width(64)
            .height(64)
            .fillColor(AppColor.textTertiary)
            .opacity(0.4)
          Text('暂无订阅分组，点击右上角 + 添加')
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: Space.md }) {
          ForEach(this.subscriptionGroups, (group: SubscriptionGroup) => {
            ListItem() {
              this.GroupRow(group)
            }
            .swipeAction({ end: this.GroupSwipeActions(group) })
          }, (group: SubscriptionGroup) => group.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.xxl })
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private HeaderActions() {
    Row({ space: Space.xs }) {
      if (this.isUpdatingAll) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(AppColor.brand)
      } else {
        IconButton({
          icon: $r('app.media.ic_refresh'),
          buttonSize: 40,
          iconSize: 24,
          iconColor: AppColor.textSecondary,
          onAction: () => {
            this.updateAllSubscriptions();
          }
        })
      }

      IconButton({
        icon: $r('app.media.ic_add'),
        buttonSize: 40,
        iconSize: 24,
        iconColor: AppColor.brand,
        onAction: () => {
          this.openAddPage();
        }
      })
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private GroupRow(group: SubscriptionGroup) {
    Row({ space: Space.md }) {
      // 图标
      Column() {
        Image(group.id === 'sub-local' ? $r('app.media.ic_folder') : $r('app.media.ic_subscriptions'))
          .width(20)
          .height(20)
          .fillColor(group.enabled || group.id === 'sub-local' ? AppColor.brand : AppColor.textTertiary)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(group.enabled || group.id === 'sub-local' ? AppColor.brandTint : AppColor.surfaceAlt)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 文本
      Column({ space: 3 }) {
        Text(group.name)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.subtitleOf(group))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatDateTime(group.updatedAt))
          .fontSize(FontSz.caption)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧：开关（订阅组）/ 箭头（本地）
      if (group.url.trim().length > 0) {
        Toggle({ type: ToggleType.Switch, isOn: group.enabled })
          .selectedColor(AppColor.brand)
          .switchPointColor(AppColor.onBrand)
          .onChange(() => {
            this.toggleSubscriptionGroup(group);
          })
      } else {
        Image($r('app.media.ic_chevron_right'))
          .width(20)
          .height(20)
          .fillColor(AppColor.textTertiary)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .onClick(() => {
      this.selectSubscriptionGroup(group);
    })
  }

  @Builder
  private GroupSwipeActions(group: SubscriptionGroup) {
    Row() {
      if (group.id !== 'sub-local') {
        this.SwipeButton($r('app.media.ic_arrow_downward'), this.t('action.moveUp'), AppColor.textSecondary, () => {
          this.moveSubscriptionGroup(group, -1);
        }, this.canMoveGroup(group.id, -1), true)
        this.SwipeButton($r('app.media.ic_arrow_downward'), this.t('action.moveDown'), AppColor.textSecondary, () => {
          this.moveSubscriptionGroup(group, 1);
        }, this.canMoveGroup(group.id, 1), false)
        if (group.url.trim().length > 0) {
          this.SwipeButton($r('app.media.ic_share'), this.t('action.share'), AppColor.brand, () => {
            this.copyUrlToClipboard(group.url);
          }, true, false)
        }
        this.SwipeButton($r('app.media.ic_edit'), this.t('action.edit'), AppColor.textSecondary, () => {
          this.openEditPage(group);
        }, true, false)
        this.SwipeButton($r('app.media.ic_delete'), this.t('action.delete'), AppColor.danger, () => {
          this.removeSubscriptionGroup(group);
        }, true, false)
      }
    }
    .height('100%')
  }

  @Builder
  private SwipeButton(icon: Resource, label: string, bg: ResourceColor, action: () => void, enabled: boolean, rotateUp: boolean) {
    Column({ space: 3 }) {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(Color.White)
        .rotate({ angle: rotateUp ? 180 : 0 })
      Text(label)
        .fontSize(FontSz.caption)
        .fontColor(Color.White)
    }
    .width(72)
    .height('100%')
    .backgroundColor(bg)
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.35)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      action();
    })
  }

  private subtitleOf(group: SubscriptionGroup): string {
    if (group.url.trim().length > 0) {
      return group.url;
    }
    if (group.id === 'sub-local') {
      return `共 ${group.nodes.length} 个本地节点`;
    }
    return `${group.nodes.length} 个节点`;
  }

  private formatDateTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '从未更新';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}`;
  }

  private async loadState(): Promise<void> {
    this.isBusy = true;
    try {
      const context = getContext(this) as common.Context;
      const settings = await SETTINGS_CONTROLLER.load(context);
      this.language = settings.language;
      this.subscriptionProxyPort = settings.appendHttpProxy && SHARED_RUNTIME_CONTROLLER.isRunning() ? LOCAL_HTTP_PROXY_PORT : 0;
      this.applySubscriptionsState(await SUBSCRIPTIONS_CONTROLLER.load(context, this.language));
    } finally {
      this.isBusy = false;
    }
  }

  private applySubscriptionsState(state: SubscriptionsControllerState): void {
    this.subscriptionGroups = state.subscriptionGroups;
    this.selectedGroupId = state.selectedGroupId;
  }

  private async selectSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    const context = getContext(this) as common.Context;
    const state = await SUBSCRIPTIONS_CONTROLLER.selectGroup(context, group, this.language);
    this.applySubscriptionsState(state);
    router.pushUrl({
      url: AppRoute.SUBSCRIPTION_DETAIL,
      params: { groupId: group.id }
    });
  }

  private async toggleSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    const context = getContext(this) as common.Context;
    const state = await SUBSCRIPTIONS_CONTROLLER.toggleGroup(context, group, this.language);
    this.applySubscriptionsState(state);
    promptAction.showToast({ message: state.subscriptionMessage });
  }

  private async removeSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    const context = getContext(this) as common.Context;
    const state = await SUBSCRIPTIONS_CONTROLLER.removeGroup(context, group, this.language);
    this.applySubscriptionsState(state);
    promptAction.showToast({ message: state.subscriptionMessage });
  }

  private async moveSubscriptionGroup(group: SubscriptionGroup, delta: number): Promise<void> {
    const context = getContext(this) as common.Context;
    const state = await SUBSCRIPTIONS_CONTROLLER.moveGroup(context, group, delta, this.language);
    this.applySubscriptionsState(state);
    promptAction.showToast({ message: state.subscriptionMessage });
  }

  private async updateAllSubscriptions(): Promise<void> {
    if (this.isUpdatingAll) {
      return;
    }
    this.isUpdatingAll = true;
    try {
      const context = getContext(this) as common.Context;
      const state = await SUBSCRIPTIONS_CONTROLLER.updateAll(context, this.language, this.subscriptionProxyPort);
      this.applySubscriptionsState(state);
      promptAction.showToast({ message: state.subscriptionMessage });
    } finally {
      this.isUpdatingAll = false;
    }
  }

  private openAddPage() {
    router.pushUrl({
      url: AppRoute.SUBSCRIPTION_EDIT
    });
  }

  private openEditPage(group: SubscriptionGroup) {
    router.pushUrl({
      url: AppRoute.SUBSCRIPTION_EDIT,
      params: { groupId: group.id }
    });
  }

  private groupIndex(groupId: string): number {
    for (let index = 0; index < this.subscriptionGroups.length; index++) {
      if (this.subscriptionGroups[index].id === groupId) {
        return index;
      }
    }
    return -1;
  }

  private canMoveGroup(groupId: string, delta: number): boolean {
    const index = this.groupIndex(groupId);
    const target = index + delta;
    return index >= 0 && target >= 0 && target < this.subscriptionGroups.length;
  }

  private copyUrlToClipboard(url: string) {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      systemPasteboard.setDataSync(pasteData);
      promptAction.showToast({ message: '订阅链接已复制到剪贴板' });
    } catch (err) {
      promptAction.showToast({ message: '复制失败' });
    }
  }

  private t(key: string): string {
    return translate(this.language, key);
  }
}
