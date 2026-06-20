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
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PER_APP_PROXY_LIST_MANAGER } from '../services/PerAppProxyListManager';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { ensureReadPasteboardPermission } from '../utils/ClipboardPermission';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

interface AppItem {
  bundleName: string;
  label: string;
  isSystem: boolean;
}

interface PresetAppItem {
  bundleName: string;
  labelKey: string;
  isSystem: boolean;
}

const SELF_BUNDLE_NAME: string = 'com.lmlm.hey';

const PRESET_APPS: PresetAppItem[] = [
  { bundleName: 'com.huawei.hbrowser', labelKey: 'perApp.preset.huaweiBrowser', isSystem: true },
  { bundleName: 'com.tencent.mm', labelKey: 'perApp.preset.wechat', isSystem: false },
  { bundleName: 'com.eg.android.AlipayGphone', labelKey: 'perApp.preset.alipay', isSystem: false },
  { bundleName: 'com.ss.android.ugc.aweme', labelKey: 'perApp.preset.douyin', isSystem: false },
  { bundleName: 'com.netease.cloudmusic', labelKey: 'perApp.preset.neteaseMusic', isSystem: false },
  { bundleName: 'com.sina.weibo', labelKey: 'perApp.preset.weibo', isSystem: false },
  { bundleName: 'com.sankuai.meituan', labelKey: 'perApp.preset.meituan', isSystem: false },
  { bundleName: 'com.xunmeng.pinduoduo', labelKey: 'perApp.preset.pinduoduo', isSystem: false },
  { bundleName: 'com.huawei.music', labelKey: 'perApp.preset.huaweiMusic', isSystem: true },
  { bundleName: 'com.huawei.photos', labelKey: 'perApp.preset.gallery', isSystem: true },
  { bundleName: 'com.huawei.appmarket', labelKey: 'perApp.preset.appGallery', isSystem: true }
];

@Entry
@Component
struct PerAppPage {
  @StorageProp('appLanguage') private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private perAppProxyEnabled: boolean = false;
  @State private perAppProxyBypass: boolean = false; // true = 黑名单(绕过), false = 白名单(代理)
  @State private perAppProxyList: string[] = []; // 被选中的包名列表

  @State private allApps: AppItem[] = []; // 设备读取到的 + 预设应用列表
  @State private searchQuery: string = ''; // 搜索关键字
  @State private newCustomPackage: string = ''; // 自定义包名输入框内容
  @State private newCustomLabel: string = ''; // 自定义包名标签名输入框内容
  @State private showManualInput: boolean = false; // 「手动添加包名」虚线卡是否展开输入区
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
    SHARED_RUNTIME_CONTROLLER.appendLog(this.t('perApp.log.loaded'));

    // 将预置常用应用包名合并，并在此处显式排除掉当前应用自身，防止本应用出现在可选列表中
    PRESET_APPS.forEach(preset => {
      if (preset.bundleName !== SELF_BUNDLE_NAME && !list.some(item => item.bundleName === preset.bundleName)) {
        list.push({
          bundleName: preset.bundleName,
          label: this.t(preset.labelKey),
          isSystem: preset.isSystem
        });
      }
    });

    // 确保之前用户保存的已经在 list 中（万一有用户手动输入的，也把它加进去，并过滤剔除可能残留的自身包名）
    this.perAppProxyList.forEach(pkg => {
      if (pkg !== SELF_BUNDLE_NAME && !list.some(item => item.bundleName === pkg)) {
        list.push({
          bundleName: pkg,
          label: this.f1('perApp.customLabel', 'package', pkg),
          isSystem: false
        });
      }
    });

    this.allApps = list;
  }

  // 过滤后的应用列表（按搜索关键字过滤名称 / 包名）
  private getFilteredApps(): AppItem[] {
    return this.allApps.filter(app => {
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
        showBack: true
      })

      if (this.perAppProxyEnabled) {
        Scroll() {
          Column({ space: Space.md }) {
            this.EnableCard()
            this.GroupLabel(this.t('perApp.section.filterStrategy'))
            this.ModeSegment()
            this.SearchField()
            this.PillRow()
            this.ListHeader()
            this.AppListCard()
            this.ManualAddCard()
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.xxl })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      } else {
        Column() {
          this.EnableCard()
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.md })
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
      .margin({ left: 14 })
  }

  @Builder
  private GroupLabel(text: string) {
    Text(text)
      .fontSize(FontSz.footnote)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColor.textTertiary)
      .width('100%')
      .padding({ left: Space.xs })
  }

  // 启用开关卡（关闭时整页仅留此卡）
  @Builder
  private EnableCard() {
    Row({ space: Space.md }) {
      Column({ space: 3 }) {
        Text(this.t('perApp.enable.title'))
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(this.t('perApp.enable.detail'))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.perAppProxyEnabled })
        .selectedColor(AppColor.brand)
        .switchPointColor(AppColor.onBrand)
        .onChange((isOn: boolean) => {
          this.perAppProxyEnabled = isOn;
          this.saveSettings();
        })
    }
    .width('100%')
    .padding({ left: Space.lg, right: Space.lg, top: 13, bottom: 13 })
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .border({ width: 0.5, color: AppColor.border })
  }

  // 过滤策略：分段控件 + 释义
  @Builder
  private ModeSegment() {
    Column({ space: Space.sm }) {
      Row({ space: 3 }) {
        this.ModeSegmentItem(this.t('perApp.mode.bypass'), true)
        this.ModeSegmentItem(this.t('perApp.mode.proxy'), false)
      }
      .width('100%')
      .padding(3)
      .backgroundColor(AppColor.surfaceAlt)
      .borderRadius(Radius.md)

      Text(this.perAppProxyBypass ? this.t('perApp.mode.bypass.hint') : this.t('perApp.mode.proxy.hint'))
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textTertiary)
        .width('100%')
        .padding({ left: Space.xs, right: Space.xs })
    }
    .width('100%')
  }

  // isBypass 是静态判别（绕过段=true / 代理段=false）；选中态从 state 现读，避免 @Builder 形参冻结
  @Builder
  private ModeSegmentItem(label: string, isBypass: boolean) {
    Row() {
      Text(label)
        .fontSize(FontSz.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.perAppProxyBypass === isBypass ? AppColor.brand : AppColor.textSecondary)
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(9)
    .backgroundColor(this.perAppProxyBypass === isBypass ? AppColor.surface : Color.Transparent)
    .shadow(this.perAppProxyBypass === isBypass ? { radius: 4, color: AppColor.shadowCard, offsetX: 0, offsetY: 1 } : undefined)
    .onClick(() => {
      if (this.perAppProxyBypass !== isBypass) {
        this.perAppProxyBypass = isBypass;
        this.saveSettings();
      }
    })
  }

  @Builder
  private SearchField() {
    Search({ placeholder: this.t('perApp.searchPlaceholder'), value: this.searchQuery })
      .width('100%')
      .height(40)
      .backgroundColor(AppColor.surfaceAlt)
      .placeholderColor(AppColor.textTertiary)
      .placeholderFont({ size: FontSz.body })
      .textFont({ size: FontSz.body })
      .onChange((val: string) => {
        this.searchQuery = val;
      })
  }

  // 批量操作胶囊（横向滚动）
  @Builder
  private PillRow() {
    Scroll() {
      Row({ space: Space.sm }) {
        this.Pill(this.t('perApp.action.selectAll'), () => {
          this.selectAllVisibleApps();
        })
        this.Pill(this.t('perApp.action.smart'), () => {
          this.autoSelectProxyApps();
        })
        this.Pill(this.t('perApp.action.invert'), () => {
          this.invertVisibleApps();
        })
        this.Pill(this.t('perApp.action.clear'), () => {
          this.clearVisibleApps();
        })
        this.Pill(this.t('perApp.action.import'), () => {
          this.importProxyAppsFromClipboard();
        })
        this.Pill(this.t('perApp.action.export'), () => {
          this.exportProxyAppsToClipboard();
        })
      }
      .padding({ right: Space.lg })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private Pill(label: string, action: () => void) {
    Text(label)
      .fontSize(FontSz.footnote)
      .fontColor(AppColor.textPrimary)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(AppColor.surface)
      .borderRadius(Radius.pill)
      .border({ width: 0.5, color: AppColor.border })
      .onClick(action)
  }

  @Builder
  private ListHeader() {
    Row() {
      Text(this.t('perApp.section.appList'))
        .fontSize(FontSz.footnote)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textTertiary)
        .layoutWeight(1)
      Text(this.f1('perApp.selectedShort', 'count', this.perAppProxyList.length.toString()))
        .fontSize(FontSz.footnote)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.brand)
    }
    .width('100%')
    .padding({ left: Space.xs, right: Space.xs })
  }

  @Builder
  private AppListCard() {
    Column() {
      ForEach(this.getFilteredApps(), (app: AppItem, index: number) => {
        this.AppRow(app)
        if (index < this.getFilteredApps().length - 1) {
          this.RowDivider()
        }
      }, (item: AppItem) => item.bundleName)
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .border({ width: 0.5, color: AppColor.border })
    .clip(true)
  }

  @Builder
  private AppRow(app: AppItem) {
    Row({ space: Space.md }) {
      Stack() {
        Text(app.label.charAt(0))
          .fontSize(FontSz.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.onBrand)
      }
      .width(38)
      .height(38)
      .borderRadius(10)
      .backgroundColor(this.iconColor(app.bundleName))

      Column({ space: 1 }) {
        Text(app.label)
          .fontSize(FontSz.callout)
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

      this.AppCheck(app.bundleName)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 9, bottom: 9 })
    .onClick(() => {
      this.toggleApp(app.bundleName);
    })
  }

  // bundleName 静态传入；勾选态从 state 现读，避免 @Builder 形参冻结导致勾选不刷新
  @Builder
  private AppCheck(bundleName: string) {
    Stack() {
      if (this.perAppProxyList.includes(bundleName)) {
        Image($r('app.media.ic_check'))
          .width(14)
          .height(14)
          .fillColor(AppColor.onBrand)
      }
    }
    .width(24)
    .height(24)
    .borderRadius(12)
    .backgroundColor(this.perAppProxyList.includes(bundleName) ? AppColor.brand : Color.Transparent)
    .border({ width: 2, color: this.perAppProxyList.includes(bundleName) ? AppColor.brand : AppColor.border })
  }

  // 底部「手动添加包名」虚线卡，点开后展开录入区
  @Builder
  private ManualAddCard() {
    Column({ space: Space.sm }) {
      Row({ space: Space.sm }) {
        Image($r('app.media.ic_add'))
          .width(18)
          .height(18)
          .fillColor(AppColor.brand)
        Text(this.t('perApp.action.addManual'))
          .fontSize(FontSz.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.brand)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding(13)
      .borderRadius(14)
      .border({ width: 1, color: AppColor.border, style: BorderStyle.Dashed })
      .backgroundColor(AppColor.surface)
      .onClick(() => {
        this.showManualInput = !this.showManualInput;
      })

      if (this.showManualInput) {
        Column() {
          TextInput({ placeholder: this.t('perApp.manualLabel.placeholder'), text: this.newCustomLabel })
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
          TextInput({ placeholder: this.t('perApp.manualPackage.placeholder'), text: this.newCustomPackage })
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
        .border({ width: 0.5, color: AppColor.border })
        .clip(true)

        Button(this.t('perApp.action.addToList'))
          .height(46)
          .width('100%')
          .backgroundColor(AppColor.brand)
          .fontColor(AppColor.onBrand)
          .fontWeight(FontWeight.Medium)
          .borderRadius(Radius.pill)
          .onClick(() => {
            this.addCustomPackage();
          })
      }
    }
    .width('100%')
  }

  // 由包名稳定派生一个图标底色（明暗通用）
  private iconColor(bundleName: string): ResourceColor {
    const palette: string[] = ['#07C160', '#1677FF', '#FF6A00', '#E72410', '#E6162D', '#FFC300', '#5B6CF0', '#0EA5E9', '#8B5CF6', '#16A34A'];
    let hash = 0;
    for (let index = 0; index < bundleName.length; index++) {
      hash = (hash * 31 + bundleName.charCodeAt(index)) % 1000000;
    }
    return palette[hash % palette.length];
  }

  private toggleApp(bundleName: string): void {
    if (this.perAppProxyList.includes(bundleName)) {
      this.perAppProxyList = this.perAppProxyList.filter((pkg: string) => pkg !== bundleName);
    } else {
      this.perAppProxyList = [...this.perAppProxyList, bundleName];
    }
    this.saveSettings();
  }

  // 手动新增包名逻辑
  private addCustomPackage(): void {
    const pkg = this.newCustomPackage.trim();
    const label = this.newCustomLabel.trim() || this.f1('perApp.customLabel', 'package', pkg);
    if (pkg.length === 0) {
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('perApp.log.addEmpty'));
      return;
    }
    if (!pkg.includes('.') || pkg.length < 5) {
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('perApp.log.addInvalid'));
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
      this.perAppProxyList = [...this.perAppProxyList, pkg];
    }
    this.saveSettings();

    // 清空输入框并收起录入区
    this.newCustomPackage = '';
    this.newCustomLabel = '';
    this.showManualInput = false;
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('perApp.log.added', 'label', label));
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
      const sourceLabel = packageList.source === 'remote' ? this.t('perApp.autoSource.remote') :
        this.t('perApp.autoSource.fallback');
      SHARED_RUNTIME_CONTROLLER.appendLog(`${message} (${sourceLabel})`);
      if (packageList.source === 'fallback' && packageList.error.length > 0) {
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('perApp.log.autoFallback', 'error', packageList.error));
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
