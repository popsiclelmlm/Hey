import { common } from '@kit.AbilityKit';
import { IconButton } from '../components/IconButton';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, SubscriptionGroup } from '../core/Profile';
import { SUBSCRIPTIONS_CONTROLLER, SubscriptionsControllerState } from '../features/subscriptions/SubscriptionsController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

@Entry
@Component
struct SubscriptionsPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private subscriptionGroups: Array<SubscriptionGroup> = [];
  @State private selectedGroupId: string = '';
  @State private isUpdatingAll: boolean = false;
  @State private isBusy: boolean = false;

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

      Scroll() {
        Column({ space: 14 }) {
          if (this.subscriptionGroups.length === 0) {
            Column({ space: 16 }) {
              Image($r('app.media.ic_subscriptions'))
                .width(64)
                .height(64)
                .fillColor('#9CA3AF')
              Text('暂无订阅分组，点击右上角 + 添加')
                .fontSize(14)
                .fontColor('#9CA3AF')
            }
            .width('100%')
            .height(300)
            .justifyContent(FlexAlign.Center)
          } else {
            ForEach(this.subscriptionGroups, (group: SubscriptionGroup) => {
              this.GroupCardItem(group)
            }, (group: SubscriptionGroup) => group.id)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F3F4F6')
  }

  // 顶部操作栏构建器
  @Builder
  private HeaderActions() {
    Row({ space: 8 }) {
      if (this.isUpdatingAll) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color('#1C1B1F')
      } else {
        IconButton({
          icon: $r('app.media.ic_refresh'),
          buttonSize: 40,
          iconSize: 24,
          iconColor: '#1C1B1F',
          onAction: () => {
            this.updateAllSubscriptions();
          }
        })
      }

      IconButton({
        icon: $r('app.media.ic_add'),
        buttonSize: 40,
        iconSize: 24,
        iconColor: '#1C1B1F',
        onAction: () => {
          this.openAddPage();
        }
      })
    }
    .alignItems(VerticalAlign.Center)
  }

  // 单个分组卡片组件
  @Builder
  private GroupCardItem(group: SubscriptionGroup) {
    Column() {
      // 第一行：标题 + 右侧操作（分享、编辑、删除）
      Row() {
        Text(group.name)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 4 }) {
          // 非 Default 分组且包含 url 时显示分享
          if (group.url.trim().length > 0) {
            IconButton({
              icon: $r('app.media.ic_share'),
              buttonSize: 36,
              iconSize: 20,
              iconColor: '#4B5563',
              onAction: () => {
                this.copyUrlToClipboard(group.url);
              }
            })
          }

          IconButton({
            icon: $r('app.media.ic_edit'),
            buttonSize: 36,
            iconSize: 20,
            iconColor: '#4B5563',
            onAction: () => {
              this.openEditPage(group);
            }
          })

          IconButton({
            icon: $r('app.media.ic_delete'),
            buttonSize: 36,
            iconSize: 20,
            iconColor: '#EF4444',
            onAction: () => {
              this.removeSubscriptionGroup(group);
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 有 URL 分组显示次行与末行
      if (group.url.trim().length > 0) {
        // 第二行：URL (截断)
        Text(group.url)
          .fontSize(13)
          .fontColor('#6B7280')
          .width('100%')
          .margin({ top: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 第三行：更新时间 + 右侧 Switch 开关
        Row() {
          Text(this.formatDateTime(group.updatedAt))
            .fontSize(12)
            .fontColor('#9CA3AF')

          Toggle({ type: ToggleType.Switch, isOn: group.enabled })
            .selectedColor('#F97910')
            .switchPointColor('#FFFFFF')
            .onChange(() => {
              this.toggleSubscriptionGroup(group);
            })
        }
        .width('100%')
        .margin({ top: 12 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 6, color: '#08000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      // 点击整行卡片（排除按钮和开关之后），进入详情页
      this.selectSubscriptionGroup(group);
    })
  }

  // 辅助函数：格式化时间戳
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
      this.language = (await SETTINGS_CONTROLLER.load(context)).language;
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
    // 跳转到子详情页，传递 groupId
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

  private async updateAllSubscriptions(): Promise<void> {
    if (this.isUpdatingAll) {
      return;
    }
    this.isUpdatingAll = true;
    try {
      const context = getContext(this) as common.Context;
      const state = await SUBSCRIPTIONS_CONTROLLER.updateAll(context, this.language);
      this.applySubscriptionsState(state);
      promptAction.showToast({ message: state.subscriptionMessage });
    } finally {
      this.isUpdatingAll = false;
    }
  }

  // 路由跳转至编辑页面 (新建/编辑)
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
