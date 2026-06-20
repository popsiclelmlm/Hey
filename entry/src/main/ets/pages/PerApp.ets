import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { shouldExposeLocalHttpProxyState } from '../core/LocalProxy';
import { markRuntimeSettingsRestartNeeded } from '../core/SettingsChange';
import {
  clearVisiblePerAppPackages,
  exportPerAppProxyList,
  importPerAppProxyList,
  invertVisiblePerAppPackages,
  selectAutoProxyPackages,
  selectAllPerAppPackages
} from '../core/PerAppProxy';
import { LOCAL_HTTP_PROXY_PORT } from '../core/XrayConfig';
import { AppLanguage } from '../core/Profile';
import { SettingToggleRow } from '../features/settings/SettingsControls';
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PER_APP_PROXY_LIST_MANAGER } from '../services/PerAppProxyListManager';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { ensureReadPasteboardPermission } from '../utils/ClipboardPermission';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

interface AppItem {
  bundleName: string;
  label: string;
  isSystem: boolean;
}

const SELF_BUNDLE_NAME: string = 'com.lmlm.hey';

const PRESET_APPS: AppItem[] = [
  { bundleName: 'com.huawei.hbrowser', label: '华为浏览器', isSystem: true },
  { bundleName: 'com.tencent.mm', label: '微信', isSystem: false },
  { bundleName: 'com.eg.android.AlipayGphone', label: '支付宝', isSystem: false },
  { bundleName: 'com.ss.android.ugc.aweme', label: '抖音', isSystem: false },
  { bundleName: 'com.netease.cloudmusic', label: '网易云音乐', isSystem: false },
  { bundleName: 'com.sina.weibo', label: '微博', isSystem: false },
  { bundleName: 'com.sankuai.meituan', label: '美团', isSystem: false },
  { bundleName: 'com.xunmeng.pinduoduo', label: '拼多多', isSystem: false },
  { bundleName: 'com.huawei.music', label: '华为音乐', isSystem: true },
  { bundleName: 'com.huawei.photos', label: '图库', isSystem: true },
  { bundleName: 'com.huawei.appmarket', label: '应用市场', isSystem: true }
];

@Entry
@Component
struct PerAppPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private perAppProxyEnabled: boolean = false;
  @State private perAppProxyBypass: boolean = false; // true = 黑名单(绕过), false = 白名单(代理)
  @State private perAppProxyList: string[] = []; // 被选中的包名列表

  @State private allApps: AppItem[] = []; // 设备读取到的 + 预设应用列表
  @State private showSystemApps: boolean = true; // 是否显示系统应用
  @State private searchQuery: string = ''; // 搜索关键字
  @State private newCustomPackage: string = ''; // 自定义包名输入框内容
  @State private newCustomLabel: string = ''; // 自定义包名标签名输入框内容
  @State private isAutoSelectingProxyApps: boolean = false;

  private draft: SettingsDraft | null = null;

  aboutToAppear(): void {
    this.loadState().then(() => {
      this.loadInstalledApps();
    });
  }

  // 加载设备上的应用列表，并合并预设与自定义的列表
  private async loadInstalledApps(): Promise<void> {
    let list: AppItem[] = [];

    // 由于 HarmonyOS NEXT 三方应用权限限制，且在最新 SDK 中禁用了已安装的全局应用枚举接口，
    // 我们在此配合预设应用和自定义录入包名，从而实现完整的黑白名单规则定制。
    SHARED_RUNTIME_CONTROLLER.appendLog("已载入分应用代理列表，可通过底部手动输入追加特定包名。");

    // 将预置常用应用包名合并，并在此处显式排除掉当前应用自身，防止本应用出现在可选列表中
    PRESET_APPS.forEach(preset => {
      if (preset.bundleName !== SELF_BUNDLE_NAME && !list.some(item => item.bundleName === preset.bundleName)) {
        list.push(preset);
      }
    });

    // 确保之前用户保存的已经在 list 中（万一有用户手动输入的，也把它加进去，并过滤剔除可能残留的自身包名）
    this.perAppProxyList.forEach(pkg => {
      if (pkg !== SELF_BUNDLE_NAME && !list.some(item => item.bundleName === pkg)) {
        list.push({
          bundleName: pkg,
          label: `自定义应用 (${pkg})`,
          isSystem: false
        });
      }
    });

    this.allApps = list;
  }

  // 过滤后的应用列表
  private getFilteredApps(): AppItem[] {
    return this.allApps.filter(app => {
      // 1. 系统应用显示控制
      if (!this.showSystemApps && app.isSystem) {
        return false;
      }
      // 2. 搜索过滤
      if (this.searchQuery.trim().length > 0) {
        const query = this.searchQuery.toLowerCase();
        const labelMatch = app.label.toLowerCase().includes(query);
        const pkgMatch = app.bundleName.toLowerCase().includes(query);
        return labelMatch || pkgMatch;
      }
      return true;
    });
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.perApp.title'),
        summary: this.t('settings.vpn.detail'),
        showBack: true
      })

      if (this.perAppProxyEnabled) {
        Scroll() {
          Column({ space: Space.lg }) {
            this.MainToggleGroup()
            this.ModeGroup()
            this.AppListGroup()
            this.ManualAddGroup()
          }
          .width('100%')
          .padding({ top: Space.sm, bottom: Space.xxl })
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Column({ space: Space.lg }) {
          this.MainToggleGroup()
        }
        .width('100%')
        .padding({ top: Space.sm })

        this.DisabledPlaceholder()
      }
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
  private MainToggleGroup() {
    SectionHeader({ title: this.t('settings.perAppProxy') })
    Column() {
      SettingToggleRow({
        title: this.t('settings.perAppProxy'),
        settingKey: '',
        isEnabled: this.perAppProxyEnabled,
        action: 'perApp',
        onLabel: this.t('action.on'),
        offLabel: this.t('action.off'),
        onToggle: (_action: string) => {
          this.perAppProxyEnabled = !this.perAppProxyEnabled;
          this.saveSettings();
        }
      })
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })
  }

  @Builder
  private ModeGroup() {
    SectionHeader({ title: '过滤策略' })
    Column() {
      this.ModeRow(true, this.t('perApp.bypassSelected.title'), this.t('perApp.bypassSelected.detail'))
      this.RowDivider()
      this.ModeRow(false, this.t('perApp.proxySelected.title'), this.t('perApp.proxySelected.detail'))
      this.RowDivider()
      this.SystemVisibilityRow()
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })
  }

  @Builder
  private ModeRow(bypass: boolean, title: string, detail: string) {
    Row({ space: Space.md }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.perAppProxyBypass === bypass ? AppColor.brand : AppColor.textPrimary)
        Text(detail)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.perAppProxyBypass === bypass) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(AppColor.brand)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      if (this.perAppProxyBypass !== bypass) {
        this.perAppProxyBypass = bypass;
        this.saveSettings();
      }
    })
  }

  @Builder
  private SystemVisibilityRow() {
    Row({ space: Space.md }) {
      Column({ space: 3 }) {
        Text(this.t('perApp.systemVisibility.title'))
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(this.t('perApp.systemVisibility.detail'))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.showSystemApps })
        .selectedColor(AppColor.brand)
        .switchPointColor(AppColor.onBrand)
        .onChange((isOn: boolean) => {
          this.showSystemApps = isOn;
        })
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private AppListGroup() {
    SectionHeader({
      title: '应用列表',
      detail: `已选 ${this.perAppProxyList.length} 个应用`
    })

    // 搜索栏（分组背景上的独立搜索条）
    Search({ placeholder: '搜索应用名称或包名', value: this.searchQuery })
      .height(40)
      .backgroundColor(AppColor.surface)
      .placeholderColor(AppColor.textTertiary)
      .margin({ left: Space.lg, right: Space.lg })
      .onChange((val: string) => {
        this.searchQuery = val;
      })

    Column() {
      this.SelectionActionRow()

      ForEach(this.getFilteredApps(), (app: AppItem) => {
        this.RowDivider()
        this.AppRow(app)
      }, (item: AppItem) => item.bundleName)
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })
  }

  @Builder
  private SelectionActionRow() {
    Column({ space: Space.sm }) {
      Row({ space: Space.lg }) {
        this.SelectionActionText(this.t('perApp.action.selectAll'), AppColor.brand, () => {
          this.selectAllVisibleApps();
        })
        this.SelectionActionText(this.t('perApp.action.invert'), AppColor.brand, () => {
          this.invertVisibleApps();
        })
        this.SelectionActionText(this.t('perApp.action.clear'), AppColor.danger, () => {
          this.clearVisibleApps();
        })
        Blank()
      }
      .width('100%')

      Row({ space: Space.lg }) {
        this.SelectionActionText(this.t('perApp.action.autoProxy'), AppColor.brand, () => {
          this.autoSelectProxyApps();
        })
        this.SelectionActionText(this.t('perApp.action.import'), AppColor.brand, () => {
          this.importProxyAppsFromClipboard();
        })
        this.SelectionActionText(this.t('perApp.action.export'), AppColor.brand, () => {
          this.exportProxyAppsToClipboard();
        })
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private SelectionActionText(label: string, color: ResourceColor, action: () => void) {
    Text(label)
      .fontSize(FontSz.body)
      .fontColor(color)
      .onClick(action)
  }

  @Builder
  private AppRow(app: AppItem) {
    Row({ space: Space.md }) {
      // 圆形应用图标占位区
      Row() {
        Text(app.label.charAt(0))
          .fontSize(FontSz.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.onBrand)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(app.isSystem ? AppColor.textTertiary : AppColor.brand)
      .justifyContent(FlexAlign.Center)

      Column({ space: 3 }) {
        Text(app.label)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(app.bundleName)
          .fontSize(FontSz.caption)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Checkbox({ name: app.bundleName, group: 'apps' })
        .selectedColor(AppColor.brand)
        .select(this.perAppProxyList.includes(app.bundleName))
        .onChange((selected: boolean) => {
          if (selected) {
            if (!this.perAppProxyList.includes(app.bundleName)) {
              this.perAppProxyList.push(app.bundleName);
            }
          } else {
            this.perAppProxyList = this.perAppProxyList.filter(pkg => pkg !== app.bundleName);
          }
          this.saveSettings();
        })
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private ManualAddGroup() {
    SectionHeader({ title: '手动添加', detail: '添加未列出的应用包名' })
    Column() {
      TextInput({ placeholder: '应用名称 (如：百度地图)', text: this.newCustomLabel })
        .fontSize(FontSz.body)
        .height(48)
        .width('100%')
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .padding({ left: Space.lg, right: Space.lg })
        .onChange((v: string) => {
          this.newCustomLabel = v;
        })
      this.RowDivider()
      TextInput({ placeholder: '应用包名 (如：com.baidu.BaiduMap)', text: this.newCustomPackage })
        .fontSize(FontSz.body)
        .height(48)
        .width('100%')
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .padding({ left: Space.lg, right: Space.lg })
        .onChange((v: string) => {
          this.newCustomPackage = v;
        })
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })

    Button('添加到列表')
      .height(46)
      .width('100%')
      .backgroundColor(AppColor.brand)
      .fontColor(AppColor.onBrand)
      .fontWeight(FontWeight.Medium)
      .borderRadius(Radius.pill)
      .margin({ left: Space.lg, right: Space.lg, top: Space.sm })
      .onClick(() => {
        this.addCustomPackage();
      })
  }

  @Builder
  private DisabledPlaceholder() {
    Column({ space: Space.lg }) {
      Image($r('app.media.ic_apps'))
        .width(64)
        .height(64)
        .fillColor(AppColor.textTertiary)
        .opacity(0.3)
      Text('分应用代理已关闭')
        .fontSize(FontSz.headline)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textTertiary)
      Text('当前所有应用的流量均会默认经过虚拟网卡代理，开启后可按应用精准分流。')
        .fontSize(FontSz.body)
        .fontColor(AppColor.textTertiary)
        .textAlign(TextAlign.Center)
        .width('80%')
        .lineHeight(20)
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  // 手动新增包名逻辑
  private addCustomPackage(): void {
    const pkg = this.newCustomPackage.trim();
    const label = this.newCustomLabel.trim() || `自定义应用 (${pkg})`;
    if (pkg.length === 0) {
      SHARED_RUNTIME_CONTROLLER.appendLog("添加包名失败: 包名不能为空。");
      return;
    }
    if (!pkg.includes('.') || pkg.length < 5) {
      SHARED_RUNTIME_CONTROLLER.appendLog("添加包名失败: 输入的包名格式不合规。");
      return;
    }

    // 检查是否已经存在于所有应用中，如果不存在，则加入
    if (!this.allApps.some(app => app.bundleName === pkg)) {
      const updated = [...this.allApps];
      updated.push({
        bundleName: pkg,
        label,
        isSystem: false
      });
      this.allApps = updated;
    }

    // 自动勾选并保存
    if (!this.perAppProxyList.includes(pkg)) {
      this.perAppProxyList.push(pkg);
    }
    this.saveSettings();

    // 清空输入框
    this.newCustomPackage = '';
    this.newCustomLabel = '';
    SHARED_RUNTIME_CONTROLLER.appendLog(`已成功追加自定义代理应用: ${label}`);
  }

  private visiblePackageNames(): Array<string> {
    return this.getFilteredApps().map((app: AppItem) => app.bundleName);
  }

  private enablePerAppProxy(): void {
    if (!this.perAppProxyEnabled) {
      this.perAppProxyEnabled = true;
    }
  }

  private async selectAllVisibleApps(): Promise<void> {
    this.enablePerAppProxy();
    this.perAppProxyList = selectAllPerAppPackages(this.perAppProxyList, this.visiblePackageNames(), SELF_BUNDLE_NAME);
    await this.saveSettings();
  }

  private async clearVisibleApps(): Promise<void> {
    this.perAppProxyList = clearVisiblePerAppPackages(this.perAppProxyList, this.visiblePackageNames(), SELF_BUNDLE_NAME);
    await this.saveSettings();
  }

  private async invertVisibleApps(): Promise<void> {
    this.enablePerAppProxy();
    this.perAppProxyList = invertVisiblePerAppPackages(this.perAppProxyList, this.visiblePackageNames(), SELF_BUNDLE_NAME);
    await this.saveSettings();
  }

  private async autoSelectProxyApps(): Promise<void> {
    if (this.isAutoSelectingProxyApps) {
      return;
    }
    this.isAutoSelectingProxyApps = true;
    this.enablePerAppProxy();
    promptAction.showToast({ message: this.f1('assets.downloading', 'title', this.t('perApp.action.autoProxy')) });
    try {
      const packageList = await PER_APP_PROXY_LIST_MANAGER.loadProxyPackageList(this.resolveAutoProxyListProxyPort());
      this.perAppProxyList = selectAutoProxyPackages(
        this.visiblePackageNames(),
        this.perAppProxyBypass,
        packageList.content,
        SELF_BUNDLE_NAME
      );
      await this.saveSettings();
      const message = this.f1('perApp.autoSelected', 'count', this.perAppProxyList.length.toString());
      promptAction.showToast({ message });
      const sourceLabel = packageList.source === 'remote' ? 'v2rayNG 远程列表' : '内置列表';
      SHARED_RUNTIME_CONTROLLER.appendLog(`${message}（${sourceLabel}）`);
      if (packageList.source === 'fallback' && packageList.error.length > 0) {
        SHARED_RUNTIME_CONTROLLER.appendLog(`自动选择代理应用列表下载失败，已使用内置列表：${packageList.error}`);
      }
    } finally {
      this.isAutoSelectingProxyApps = false;
    }
  }

  private resolveAutoProxyListProxyPort(): number {
    if (this.draft !== null && shouldExposeLocalHttpProxyState(
      this.draft.mode,
      this.draft.appendHttpProxy,
      this.draft.localSocksEnabled
    ) && SHARED_RUNTIME_CONTROLLER.isRunning()) {
      return LOCAL_HTTP_PROXY_PORT;
    }
    return 0;
  }

  private async importProxyAppsFromClipboard(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      if (!await ensureReadPasteboardPermission(context)) {
        promptAction.showToast({ message: this.t('prompt.clipboardEmpty') });
        return;
      }
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (!systemPasteboard.hasDataSync()) {
        promptAction.showToast({ message: this.t('prompt.clipboardEmpty') });
        return;
      }
      const pasteData = await systemPasteboard.getData();
      const text = pasteData.getPrimaryText();
      if (!text || text.trim().length === 0) {
        promptAction.showToast({ message: this.t('prompt.clipboardEmpty') });
        return;
      }

      const result = importPerAppProxyList(text, this.perAppProxyBypass, SELF_BUNDLE_NAME);
      if (!result.success) {
        promptAction.showToast({ message: this.t('perApp.importFailed') });
        return;
      }
      this.perAppProxyBypass = result.bypass;
      this.perAppProxyList = result.packages;
      this.enablePerAppProxy();
      await this.saveSettings();
      const message = this.f1('perApp.imported', 'count', result.count.toString());
      promptAction.showToast({ message });
      SHARED_RUNTIME_CONTROLLER.appendLog(message);
    } catch (error) {
      promptAction.showToast({ message: this.t('perApp.importFailed') });
      SHARED_RUNTIME_CONTROLLER.appendLog(JSON.stringify(error));
    }
  }

  private async exportProxyAppsToClipboard(): Promise<void> {
    const systemPasteboard = pasteboard.getSystemPasteboard();
    const pasteData = pasteboard.createData(
      pasteboard.MIMETYPE_TEXT_PLAIN,
      exportPerAppProxyList(this.perAppProxyBypass, this.perAppProxyList, SELF_BUNDLE_NAME)
    );
    await systemPasteboard.setData(pasteData);
    const message = this.f1('perApp.exported', 'count', this.perAppProxyList.length.toString());
    promptAction.showToast({ message });
    SHARED_RUNTIME_CONTROLLER.appendLog(message);
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.draft = SETTINGS_CONTROLLER.toDraft(await SETTINGS_CONTROLLER.load(context));
    this.language = this.draft.language;
    this.perAppProxyEnabled = this.draft.perAppProxyEnabled;
    this.perAppProxyList = this.draft.perAppProxyList ?? [];
    this.perAppProxyBypass = this.draft.perAppProxyBypass ?? false;
  }

  private async saveSettings(): Promise<void> {
    if (this.draft === null) {
      return;
    }
    this.draft.perAppProxyEnabled = this.perAppProxyEnabled;
    this.draft.perAppProxyList = this.perAppProxyList;
    this.draft.perAppProxyBypass = this.perAppProxyBypass;
    const context = getContext(this) as common.Context;
    this.draft = SETTINGS_CONTROLLER.toDraft(await SETTINGS_CONTROLLER.save(context, this.draft));
    markRuntimeSettingsRestartNeeded();
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', 'perApp'));
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
