import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import {
  APP_LANGUAGE_AUTO,
  APP_LANGUAGE_EN,
  APP_LANGUAGE_ZH_CN,
  APP_LANGUAGE_ZH_TW,
  APP_MODE_VPN,
  AppLanguage,
  DEFAULT_DELAY_TEST_URL,
  DEFAULT_HEV_TUN_LOG_LEVEL,
  DEFAULT_HEV_TUN_RW_TIMEOUT,
  DEFAULT_IP_API_URL,
  DEFAULT_VPN_MTU,
  normalizeAppRuntimeMode,
  normalizeHevTunLogLevel,
  OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS,
  OutboundDomainResolveMethod,
  resolveVpnInterfaceAddressConfig,
  RoutingRule,
  UI_MODE_NIGHT_SYSTEM,
  VPN_BYPASS_LAN_BYPASS,
  VPN_INTERFACE_ADDRESS_CONFIGS
} from '../core/Profile';
import { applyColorMode } from '../core/ColorMode';
import { markRuntimeSettingsRestartNeeded } from '../core/SettingsChange';
import { CLIENT_COMPAT_FRAGMENT_PACKET_OPTIONS, normalizeClientCompatCoreLogLevel, normalizeClientCompatFragmentPackets, normalizeClientCompatMuxXudpQuic } from '../core/ClientCompatOptions';
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { filterSettings, SETTINGS_CATALOG, SettingGroup, SettingInputKind, SettingItem } from '../features/settings/SettingsCatalog';
import { findInputSpec, findSelectSpec, SettingInputSpec, SettingSelectSpec } from '../features/settings/SettingsOptions';
import { CORE_TYPE_XRAY, CoreSelectionStore, CoreType } from '../core/CoreSelection';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

/** 底部抽屉里渲染的单个选择项（已按当前值算好高亮）。 */
interface SheetOptionVM {
  value: string;
  label: string;
  desc: string;
  selected: boolean;
}

@Entry
@Component
struct SettingsPage {
  @StorageLink('appLanguage') private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private settingUiModeNight: string = UI_MODE_NIGHT_SYSTEM;
  @State private settingSpeedEnabled: boolean = false;
  @State private settingConfirmRemove: boolean = false;
  @State private settingStartScanImmediate: boolean = false;
  @State private settingStartOnBoot: boolean = false;
  @State private settingCheckUpdatePreRelease: boolean = false;
  @State private settingGroupAllDisplay: boolean = false;
  @State private settingDoubleColumnDisplay: boolean = false;
  @State private settingSniffing: boolean = true;
  @State private settingRouteOnly: boolean = false;
  @State private settingLocalDns: boolean = false;
  @State private settingFakeDns: boolean = false;
  @State private settingAppendHttpProxy: boolean = false;
  @State private settingLocalSocks: boolean = true;
  @State private settingLocalSocksPort: string = '10808';
  @State private settingLocalSocksDynamicPort: boolean = false;
  @State private settingLocalSocksUdp: boolean = true;
  @State private settingLocalSocksUsername: string = '';
  @State private settingLocalSocksPassword: string = '';
  @State private settingUseHevTun: boolean = false;
  @State private settingHevTunLogLevel: string = DEFAULT_HEV_TUN_LOG_LEVEL;
  @State private settingHevTunRwTimeout: string = DEFAULT_HEV_TUN_RW_TIMEOUT;
  @State private settingMux: boolean = false;
  @State private settingMuxConcurrency: string = '8';
  @State private settingMuxXudpConcurrency: string = '8';
  @State private settingMuxXudpQuic: string = 'reject';
  @State private settingFragment: boolean = false;
  @State private settingFragmentPackets: string = 'tlshello';
  @State private settingFragmentLength: string = '50-100';
  @State private settingFragmentInterval: string = '10-20';
  @State private settingIpv6Enabled: boolean = false;
  @State private settingPreferIpv6: boolean = false;
  @State private settingProxySharing: boolean = false;
  @State private settingAllowInsecure: boolean = false;
  @State private settingPerAppProxy: boolean = false;
  @State private settingRemoteDns: string = '1.1.1.1';
  @State private settingDomesticDns: string = '223.5.5.5';
  @State private settingDnsHosts: string = '';
  @State private settingVpnDns: string = '1.1.1.1';
  @State private settingLocalDnsPort: string = '10853';
  @State private settingVpnInterfaceAddressIndex: number = 0;
  @State private settingVpnBypassLan: string = VPN_BYPASS_LAN_BYPASS;
  @State private settingVpnMtu: string = DEFAULT_VPN_MTU.toString();
  @State private settingLogLevel: string = 'warning';
  @State private settingDelayTestUrl: string = DEFAULT_DELAY_TEST_URL;
  @State private settingIpApiUrl: string = DEFAULT_IP_API_URL;
  @State private settingRealPingConcurrency: string = '16';
  @State private settingMode: string = APP_MODE_VPN;
  // 运行内核（独立存储 CoreSelectionStore，不走 AppSettings 草稿）。预览功能。
  @State private settingCoreType: string = CORE_TYPE_XRAY;
  @State private settingOutboundDomainResolveMethod: OutboundDomainResolveMethod = OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS;
  @State private settingAutoSortAfterTest: boolean = false;
  @State private settingAutoRemoveAfterTest: boolean = false;
  @State private trafficMode: string = 'rules';
  @State private routingStrategy: string = 'AsIs';
  // Round-tripped only (edited on the Routing page); preserved here so saving
  // general settings does not reset routing preferences.
  @State private adBlockEnabled: boolean = false;
  @State private routingRules: Array<RoutingRule> = [];
  @State private lastError: string = '';
  @State private perAppProxyList: string[] = [];
  @State private perAppProxyBypass: boolean = false;
  // 单页长滚动 · 搜索
  @State private searchQuery: string = '';
  // 设置项弹窗（底部抽屉）· '' 关闭 / 'select' 选择 / 'input' 输入
  @State private sheetKind: string = '';
  @State private sheetKey: string = '';
  @State private sheetTitle: string = '';
  @State private sheetHint: string = '';
  @State private sheetOptions: SheetOptionVM[] = [];
  @State private sheetDraft: string = '';
  @State private sheetInputKind: SettingInputKind = 'text';
  @State private sheetUnit: string = '';
  @State private sheetRange: string = '';
  @State private sheetDefault: string = '';

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.settings.title'),
        showBack: true
      })

      Stack({ alignContent: Alignment.TopStart }) {
        List() {
          ListItem() {
            this.SearchBar()
          }

          ForEach(this.visibleSections(), (sec: SettingGroup) => {
            ListItemGroup({ header: this.GroupHeader(sec) }) {
              ListItem() {
                Column() {
                  ForEach(sec.items, (item: SettingItem, index: number) => {
                    this.SettingRow(item, index !== sec.items.length - 1)
                  }, (item: SettingItem) => item.key)
                }
                .width('100%')
                .backgroundColor(AppColor.surface)
                .borderRadius(Radius.lg)
                .border({ width: 0.5, color: AppColor.border })
                .clip(true)
              }
              .padding({ left: Space.lg, right: Space.lg, bottom: Space.md })
            }
          }, (sec: SettingGroup) => sec.id + '|' + sec.items.map((it: SettingItem) => it.key).join(','))

          ListItem() {
            this.FooterArea()
          }
        }
        .sticky(StickyStyle.Header)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.bg)

        this.SettingSheet()
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private SearchBar() {
    Row({ space: Space.sm }) {
      Image($r('app.media.ic_search'))
        .width(18)
        .height(18)
        .fillColor(AppColor.textTertiary)
      TextInput({ text: this.searchQuery, placeholder: this.t('settings.search.placeholder') })
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .borderRadius(0)
        .fontSize(FontSz.body)
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .onChange((value: string) => {
          this.searchQuery = value;
        })
      if (this.searchQuery.length > 0) {
        Stack() {
          Text('✕')
            .fontSize(11)
            .fontColor(AppColor.surfaceAlt)
        }
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(AppColor.textTertiary)
        .onClick(() => {
          this.searchQuery = '';
        })
      }
    }
    .height(40)
    .padding({ left: Space.md, right: Space.md })
    .backgroundColor(AppColor.surfaceAlt)
    .borderRadius(Radius.md)
    .margin({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.xs })
  }

  @Builder
  private GroupHeader(group: SettingGroup) {
    Row({ space: Space.md }) {
      Stack() {
        Image(this.groupIconRes(group.id))
          .width(16)
          .height(16)
      }
      .width(26)
      .height(26)
      .borderRadius(8)
      .backgroundColor(group.color)

      Text(this.t(group.titleKey))
        .fontSize(FontSz.footnote)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.textPrimary)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: Space.lg + Space.xs, right: Space.lg, top: Space.md, bottom: Space.sm })
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private SettingRow(item: SettingItem, showDivider: boolean) {
    Column() {
      Row({ space: Space.md }) {
        Column({ space: 3 }) {
          Text(this.t(item.titleKey))
            .fontSize(FontSz.callout)
            .fontColor(item.danger === true ? AppColor.danger : AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.descKey !== undefined) {
            Text(this.t(item.descKey))
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.textTertiary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (item.type === 'toggle') {
          Toggle({ type: ToggleType.Switch, isOn: this.toggleValue(item.key) })
            .selectedColor(AppColor.brand)
            .switchPointColor(AppColor.onBrand)
            .hitTestBehavior(HitTestMode.None)
        } else if (item.type === 'option') {
          Row({ space: 2 }) {
            Text(this.settingOptionValue(item.key))
              .fontSize(FontSz.body)
              .fontColor(AppColor.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Image($r('app.media.ic_chevron_right'))
              .width(18)
              .height(18)
              .fillColor(AppColor.textTertiary)
          }
          .constraintSize({ maxWidth: '55%' })
        } else if (item.type === 'input') {
          Text(this.inputDisplay(item.key))
            .fontSize(FontSz.body)
            .fontColor(this.currentInputValue(item.key).length > 0 ? AppColor.textSecondary : AppColor.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '55%' })
        } else {
          Image($r('app.media.ic_chevron_right'))
            .width(18)
            .height(18)
            .fillColor(AppColor.textTertiary)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 54 })
      .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.sm })
      .onClick(() => {
        this.onRowTap(item);
      })

      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(AppColor.divider)
          .margin({ left: Space.lg })
      }
    }
    .width('100%')
  }

  @Builder
  private FooterArea() {
    Column({ space: Space.sm }) {
      if (this.searchQuery.trim().length > 0 && this.visibleSections().length === 0) {
        Text(this.f1('settings.search.empty', 'query', this.searchQuery.trim()))
          .fontSize(FontSz.callout)
          .fontColor(AppColor.textTertiary)
        Text(this.t('settings.search.emptyHint'))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      } else if (this.searchQuery.trim().length === 0) {
        Text(this.t('settings.instantEffectFooter'))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      }

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
    }
    .width('100%')
    .padding({ top: Space.lg, bottom: Space.xxl })
  }

  private groupIconRes(id: string): Resource {
    switch (id) {
      case 'ui':
        return $r('app.media.ic_set_grp_ui');
      case 'core':
        return $r('app.media.ic_set_grp_core');
      case 'vpn':
        return $r('app.media.ic_set_grp_vpn');
      case 'transport':
        return $r('app.media.ic_set_grp_transport');
      case 'advanced':
        return $r('app.media.ic_set_grp_advanced');
      default:
        return $r('app.media.ic_set_grp_testing');
    }
  }

  private onRowTap(item: SettingItem): void {
    if (item.type === 'toggle') {
      this.toggleSetting(item.key);
      return;
    }
    if (item.type === 'option') {
      this.openSelectSheet(item);
      return;
    }
    if (item.type === 'input') {
      this.openInputSheet(item);
      return;
    }
    if (item.route !== undefined && item.route.length > 0) {
      this.getUIContext().getRouter().pushUrl({ url: item.route }).catch((err: Error) => {});
    }
  }

  private inputDisplay(key: string): string {
    const value = this.currentInputValue(key);
    return value.length > 0 ? value : this.t('settings.value.unset');
  }

  private visibleSections(): SettingGroup[] {
    const sections = filterSettings(
      SETTINGS_CATALOG,
      (key: string): boolean => this.isEnabled(key),
      this.searchQuery,
      (key: string): string => this.t(key)
    );
    if (this.isMuxXudpQuicAvailable()) {
      return sections;
    }
    const result: SettingGroup[] = [];
    for (const group of sections) {
      if (group.id !== 'transport') {
        result.push(group);
        continue;
      }
      const items: SettingItem[] = group.items.filter((it: SettingItem): boolean => it.key !== 'muxXudpQuic');
      if (items.length > 0) {
        result.push({ id: group.id, titleKey: group.titleKey, color: group.color, items: items });
      }
    }
    return result;
  }

  private isEnabled(key: string): boolean {
    return this.toggleValue(key);
  }

  private toggleValue(key: string): boolean {
    switch (key) {
      case 'speedEnabled': return this.settingSpeedEnabled;
      case 'confirmRemove': return this.settingConfirmRemove;
      case 'startScanImmediate': return this.settingStartScanImmediate;
      case 'startOnBoot': return this.settingStartOnBoot;
      case 'checkUpdatePreRelease': return this.settingCheckUpdatePreRelease;
      case 'groupAllDisplay': return this.settingGroupAllDisplay;
      case 'doubleColumnDisplay': return this.settingDoubleColumnDisplay;
      case 'sniffing': return this.settingSniffing;
      case 'routeOnly': return this.settingRouteOnly;
      case 'allowInsecure': return this.settingAllowInsecure;
      case 'localDns': return this.settingLocalDns;
      case 'fakeDns': return this.settingFakeDns;
      case 'proxySharing': return this.settingProxySharing;
      case 'appendHttpProxy': return this.settingAppendHttpProxy;
      case 'localSocks': return this.settingLocalSocks;
      case 'localSocksDynamicPort': return this.settingLocalSocksDynamicPort;
      case 'localSocksUdp': return this.settingLocalSocksUdp;
      case 'useHevTun': return this.settingUseHevTun;
      case 'ipv6Enabled': return this.settingIpv6Enabled;
      case 'preferIpv6': return this.settingPreferIpv6;
      case 'mux': return this.settingMux;
      case 'fragment': return this.settingFragment;
      case 'autoSortAfterTest': return this.settingAutoSortAfterTest;
      case 'autoRemoveAfterTest': return this.settingAutoRemoveAfterTest;
      default: return false;
    }
  }

  private currentInputValue(key: string): string {
    switch (key) {
      case 'localDnsPort': return this.settingLocalDnsPort;
      case 'localSocksPort': return this.settingLocalSocksPort;
      case 'localSocksUsername': return this.settingLocalSocksUsername;
      case 'localSocksPassword': return this.settingLocalSocksPassword;
      case 'hevTunRwTimeout': return this.settingHevTunRwTimeout;
      case 'vpnDns': return this.settingVpnDns;
      case 'vpnMtu': return this.settingVpnMtu;
      case 'muxConcurrency': return this.settingMuxConcurrency;
      case 'muxXudpConcurrency': return this.settingMuxXudpConcurrency;
      case 'fragmentLength': return this.settingFragmentLength;
      case 'fragmentInterval': return this.settingFragmentInterval;
      case 'remoteDns': return this.settingRemoteDns;
      case 'domesticDns': return this.settingDomesticDns;
      case 'dnsHosts': return this.settingDnsHosts;
      case 'delayTestUrl': return this.settingDelayTestUrl;
      case 'ipApiUrl': return this.settingIpApiUrl;
      case 'realPingConcurrency': return this.settingRealPingConcurrency;
      default: return '';
    }
  }

  private settingOptionValue(action: string): string {
    if (action === 'language') {
      return this.languageLabel(this.language);
    }
    if (action === 'vpnInterfaceAddress') {
      return this.vpnInterfaceAddressLabel();
    }
    if (action === 'fragmentPackets') {
      return this.fragmentPacketsLabel();
    }
    const spec: SettingSelectSpec | undefined = findSelectSpec(action);
    if (spec === undefined) {
      return '';
    }
    const current = this.currentOptionValue(action);
    for (let index = 0; index < spec.choices.length; index++) {
      if (spec.choices[index].value === current) {
        return this.t(spec.choices[index].labelKey);
      }
    }
    return '';
  }

  private async loadState(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      this.applyDraft(SETTINGS_CONTROLLER.toDraft(await SETTINGS_CONTROLLER.load(context)));
      this.settingCoreType = await CoreSelectionStore.load(context);
    } catch (error) {
      this.lastError = this.f1('error.loadSettings', 'error', JSON.stringify(error));
    }
  }

  private toggleSetting(action: string): void {
    switch (action) {
      case 'sniffing':
        this.settingSniffing = !this.settingSniffing;
        break;
      case 'speedEnabled':
        this.settingSpeedEnabled = !this.settingSpeedEnabled;
        break;
      case 'confirmRemove':
        this.settingConfirmRemove = !this.settingConfirmRemove;
        break;
      case 'startScanImmediate':
        this.settingStartScanImmediate = !this.settingStartScanImmediate;
        break;
      case 'startOnBoot':
        this.settingStartOnBoot = !this.settingStartOnBoot;
        break;
      case 'checkUpdatePreRelease':
        this.settingCheckUpdatePreRelease = !this.settingCheckUpdatePreRelease;
        break;
      case 'groupAllDisplay':
        this.settingGroupAllDisplay = !this.settingGroupAllDisplay;
        break;
      case 'doubleColumnDisplay':
        this.settingDoubleColumnDisplay = !this.settingDoubleColumnDisplay;
        break;
      case 'routeOnly':
        this.settingRouteOnly = !this.settingRouteOnly;
        break;
      case 'localDns':
        this.settingLocalDns = !this.settingLocalDns;
        if (!this.settingLocalDns) {
          this.settingFakeDns = false;
        }
        break;
      case 'fakeDns':
        this.settingFakeDns = this.settingLocalDns ? !this.settingFakeDns : false;
        break;
      case 'mux':
        this.settingMux = !this.settingMux;
        break;
      case 'fragment':
        this.settingFragment = !this.settingFragment;
        break;
      case 'ipv6Enabled':
        this.settingIpv6Enabled = !this.settingIpv6Enabled;
        break;
      case 'preferIpv6':
        this.settingPreferIpv6 = !this.settingPreferIpv6;
        break;
      case 'proxySharing':
        this.settingProxySharing = this.isLocalProxyEnabled() ? !this.settingProxySharing : false;
        break;
      case 'appendHttpProxy':
        this.settingAppendHttpProxy = this.isLocalProxyEnabled() ? !this.settingAppendHttpProxy : false;
        break;
      case 'localSocks':
        this.settingLocalSocks = this.settingUseHevTun ? true : !this.settingLocalSocks;
        if (!this.settingLocalSocks) {
          this.settingAppendHttpProxy = false;
          this.settingProxySharing = false;
        }
        break;
      case 'useHevTun':
        this.settingUseHevTun = !this.settingUseHevTun;
        if (this.settingUseHevTun) {
          this.settingLocalSocks = true;
        }
        break;
      case 'localSocksDynamicPort':
        this.settingLocalSocksDynamicPort = !this.settingLocalSocksDynamicPort;
        break;
      case 'localSocksUdp':
        this.settingLocalSocksUdp = !this.settingLocalSocksUdp;
        break;
      case 'allowInsecure':
        this.settingAllowInsecure = !this.settingAllowInsecure;
        break;
      case 'perApp':
        this.settingPerAppProxy = !this.settingPerAppProxy;
        break;
      case 'autoSortAfterTest':
        this.settingAutoSortAfterTest = !this.settingAutoSortAfterTest;
        break;
      case 'autoRemoveAfterTest':
        this.settingAutoRemoveAfterTest = !this.settingAutoRemoveAfterTest;
        break;
      default:
        break;
    }
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', action));
    this.persistSettings(false);
  }

  private isLocalProxyEnabled(): boolean {
    return this.settingLocalSocks || this.settingUseHevTun;
  }

  private updateSettingInput(action: string, value: string): void {
    switch (action) {
      case 'vpnDns':
        this.settingVpnDns = value;
        break;
      case 'vpnMtu':
        this.settingVpnMtu = value;
        break;
      case 'localDnsPort':
        this.settingLocalDnsPort = value;
        break;
      case 'localSocksPort':
        this.settingLocalSocksPort = value;
        break;
      case 'localSocksUsername':
        this.settingLocalSocksUsername = value;
        break;
      case 'localSocksPassword':
        this.settingLocalSocksPassword = value;
        break;
      case 'hevTunRwTimeout':
        this.settingHevTunRwTimeout = value;
        break;
      case 'remoteDns':
        this.settingRemoteDns = value;
        break;
      case 'domesticDns':
        this.settingDomesticDns = value;
        break;
      case 'dnsHosts':
        this.settingDnsHosts = value;
        break;
      case 'delayTestUrl':
        this.settingDelayTestUrl = value;
        break;
      case 'ipApiUrl':
        this.settingIpApiUrl = value;
        break;
      case 'realPingConcurrency':
        this.settingRealPingConcurrency = value;
        break;
      case 'muxConcurrency':
        this.settingMuxConcurrency = value;
        break;
      case 'muxXudpConcurrency':
        this.settingMuxXudpConcurrency = value;
        break;
      case 'fragmentPackets':
        this.settingFragmentPackets = value;
        break;
      case 'fragmentLength':
        this.settingFragmentLength = value;
        break;
      case 'fragmentInterval':
        this.settingFragmentInterval = value;
        break;
      default:
        break;
    }
  }

  private async persistSettings(showMessage: boolean): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const saved = await SETTINGS_CONTROLLER.save(context, this.buildDraft());
      applyColorMode(context, saved.uiModeNight);
      this.applyDraft(SETTINGS_CONTROLLER.toDraft(saved));
      markRuntimeSettingsRestartNeeded();
      if (showMessage) {
        SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.settingsSaved'));
      }
      this.lastError = '';
    } catch (error) {
      this.lastError = this.f1('error.saveSettings', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    }
  }

  private languageLabel(language: AppLanguage): string {
    if (language === APP_LANGUAGE_AUTO) {
      return this.t('settings.language.auto');
    }
    if (language === APP_LANGUAGE_EN) {
      return this.t('settings.language.en');
    }
    if (language === APP_LANGUAGE_ZH_CN) {
      return this.t('settings.language.zhCn');
    }
    if (language === APP_LANGUAGE_ZH_TW) {
      return this.t('settings.language.zhTw');
    }
    if (language === 'vi') {
      return this.t('settings.language.vi');
    }
    if (language === 'ru') {
      return this.t('settings.language.ru');
    }
    if (language === 'fa') {
      return this.t('settings.language.fa');
    }
    if (language === 'ar') {
      return this.t('settings.language.ar');
    }
    if (language === 'bn') {
      return this.t('settings.language.bn');
    }
    return this.t('settings.language.bqiIr');
  }

  private buildDraft(): SettingsDraft {
    return {
      language: this.language,
      uiModeNight: this.settingUiModeNight,
      speedEnabled: this.settingSpeedEnabled,
      confirmRemove: this.settingConfirmRemove,
      startScanImmediate: this.settingStartScanImmediate,
      startOnBoot: this.settingStartOnBoot,
      checkUpdatePreRelease: this.settingCheckUpdatePreRelease,
      groupAllDisplay: this.settingGroupAllDisplay,
      doubleColumnDisplay: this.settingDoubleColumnDisplay,
      sniffingEnabled: this.settingSniffing,
      routeOnlyEnabled: this.settingRouteOnly,
      perAppProxyEnabled: this.settingPerAppProxy,
      perAppProxyList: this.perAppProxyList,
      perAppProxyBypass: this.perAppProxyBypass,
      localDnsEnabled: this.settingLocalDns,
      fakeDnsEnabled: this.settingFakeDns,
      appendHttpProxy: this.settingAppendHttpProxy,
      localSocksEnabled: this.settingLocalSocks,
      localSocksPort: this.settingLocalSocksPort,
      localSocksDynamicPort: this.settingLocalSocksDynamicPort,
      localSocksUdpEnabled: this.settingLocalSocksUdp,
      localSocksUsername: this.settingLocalSocksUsername,
      localSocksPassword: this.settingLocalSocksPassword,
      useHevTun: this.settingUseHevTun,
      hevTunLogLevel: this.settingHevTunLogLevel,
      hevTunRwTimeout: this.settingHevTunRwTimeout,
      muxEnabled: this.settingMux,
      muxConcurrency: this.settingMuxConcurrency,
      muxXudpConcurrency: this.settingMuxXudpConcurrency,
      muxXudpQuic: this.settingMuxXudpQuic,
      fragmentEnabled: this.settingFragment,
      fragmentPackets: this.settingFragmentPackets,
      fragmentLength: this.settingFragmentLength,
      fragmentInterval: this.settingFragmentInterval,
      ipv6Enabled: this.settingIpv6Enabled,
      preferIpv6: this.settingPreferIpv6,
      proxySharingEnabled: this.settingProxySharing,
      allowInsecure: this.settingAllowInsecure,
      remoteDns: this.settingRemoteDns,
      domesticDns: this.settingDomesticDns,
      dnsHosts: this.settingDnsHosts,
      localDnsPort: this.settingLocalDnsPort,
      vpnInterfaceAddressIndex: this.settingVpnInterfaceAddressIndex,
      vpnBypassLan: this.settingVpnBypassLan,
      vpnMtu: this.settingVpnMtu,
      vpnDns: this.settingVpnDns,
      logLevel: this.settingLogLevel,
      delayTestUrl: this.settingDelayTestUrl,
      ipApiUrl: this.settingIpApiUrl,
      realPingConcurrency: this.settingRealPingConcurrency,
      mode: normalizeAppRuntimeMode(this.settingMode),
      outboundDomainResolveMethod: this.settingOutboundDomainResolveMethod,
      trafficMode: this.trafficMode,
      routingDomainStrategy: this.routingStrategy,
      adBlockEnabled: this.adBlockEnabled,
      routingRules: this.copyRoutingRules(this.routingRules),
      autoSortAfterTest: this.settingAutoSortAfterTest,
      autoRemoveInvalidAfterTest: this.settingAutoRemoveAfterTest
    };
  }

  private applyDraft(draft: SettingsDraft): void {
    this.language = draft.language;
    this.settingUiModeNight = draft.uiModeNight;
    this.settingSpeedEnabled = draft.speedEnabled;
    this.settingConfirmRemove = draft.confirmRemove;
    this.settingStartScanImmediate = draft.startScanImmediate;
    this.settingStartOnBoot = draft.startOnBoot;
    this.settingCheckUpdatePreRelease = draft.checkUpdatePreRelease;
    this.settingGroupAllDisplay = draft.groupAllDisplay;
    this.settingDoubleColumnDisplay = draft.doubleColumnDisplay;
    this.settingSniffing = draft.sniffingEnabled;
    this.settingRouteOnly = draft.routeOnlyEnabled;
    this.settingPerAppProxy = draft.perAppProxyEnabled;
    this.perAppProxyList = draft.perAppProxyList ?? [];
    this.perAppProxyBypass = draft.perAppProxyBypass ?? false;
    this.settingLocalDns = draft.localDnsEnabled;
    this.settingFakeDns = draft.fakeDnsEnabled;
    this.settingAppendHttpProxy = draft.appendHttpProxy;
    this.settingLocalSocks = draft.localSocksEnabled;
    this.settingLocalSocksPort = draft.localSocksPort;
    this.settingLocalSocksDynamicPort = draft.localSocksDynamicPort;
    this.settingLocalSocksUdp = draft.localSocksUdpEnabled;
    this.settingLocalSocksUsername = draft.localSocksUsername;
    this.settingLocalSocksPassword = draft.localSocksPassword;
    this.settingUseHevTun = draft.useHevTun;
    this.settingHevTunLogLevel = draft.hevTunLogLevel;
    this.settingHevTunRwTimeout = draft.hevTunRwTimeout;
    this.settingMux = draft.muxEnabled;
    this.settingMuxConcurrency = draft.muxConcurrency;
    this.settingMuxXudpConcurrency = draft.muxXudpConcurrency;
    this.settingMuxXudpQuic = draft.muxXudpQuic;
    this.settingFragment = draft.fragmentEnabled;
    this.settingFragmentPackets = draft.fragmentPackets;
    this.settingFragmentLength = draft.fragmentLength;
    this.settingFragmentInterval = draft.fragmentInterval;
    this.settingIpv6Enabled = draft.ipv6Enabled;
    this.settingPreferIpv6 = draft.preferIpv6;
    this.settingProxySharing = draft.proxySharingEnabled;
    this.settingAllowInsecure = draft.allowInsecure;
    this.settingRemoteDns = draft.remoteDns;
    this.settingDomesticDns = draft.domesticDns;
    this.settingDnsHosts = draft.dnsHosts;
    this.settingLocalDnsPort = draft.localDnsPort;
    this.settingVpnInterfaceAddressIndex = draft.vpnInterfaceAddressIndex;
    this.settingVpnBypassLan = draft.vpnBypassLan;
    this.settingVpnMtu = draft.vpnMtu;
    this.settingVpnDns = draft.vpnDns;
    this.settingLogLevel = draft.logLevel;
    this.settingDelayTestUrl = draft.delayTestUrl;
    this.settingIpApiUrl = draft.ipApiUrl;
    this.settingRealPingConcurrency = draft.realPingConcurrency;
    this.settingMode = draft.mode;
    this.settingOutboundDomainResolveMethod = draft.outboundDomainResolveMethod;
    this.trafficMode = draft.trafficMode;
    this.routingStrategy = draft.routingDomainStrategy;
    this.adBlockEnabled = draft.adBlockEnabled;
    this.routingRules = this.copyRoutingRules(draft.routingRules);
    this.settingAutoSortAfterTest = draft.autoSortAfterTest;
    this.settingAutoRemoveAfterTest = draft.autoRemoveInvalidAfterTest;
  }

  private copyRoutingRules(rules: Array<RoutingRule>): Array<RoutingRule> {
    const result = new Array<RoutingRule>();
    for (let index = 0; index < rules.length; index++) {
      const item = rules[index];
      result.push({
        id: item.id,
        remarks: item.remarks,
        domain: item.domain.slice(),
        ip: item.ip.slice(),
        process: item.process.slice(),
        outboundTag: item.outboundTag,
        port: item.port,
        network: item.network,
        protocol: item.protocol.slice(),
        enabled: item.enabled,
        locked: item.locked
      });
    }
    return result;
  }

  // ===== 选择 / 输入 弹窗（底部抽屉）=====

  private openSelectSheet(item: SettingItem): void {
    const key = item.key;
    if (key === 'language') {
      this.getUIContext().getRouter().pushUrl({ url: AppRoute.LANGUAGE }).catch((err: Error) => {});
      return;
    }
    const options = this.buildSheetOptions(key);
    if (options.length === 0) {
      return;
    }
    this.sheetKey = key;
    this.sheetTitle = this.t(item.titleKey);
    this.sheetHint = this.sheetHintFor(key);
    this.sheetOptions = options;
    this.sheetKind = 'select';
  }

  private openInputSheet(item: SettingItem): void {
    const key = item.key;
    const spec: SettingInputSpec | undefined = findInputSpec(key);
    this.sheetKey = key;
    this.sheetTitle = this.t(item.titleKey);
    this.sheetHint = spec !== undefined && spec.hintKey.length > 0 ? this.t(spec.hintKey) : '';
    this.sheetUnit = spec !== undefined ? spec.unit : '';
    this.sheetRange = spec !== undefined ? spec.range : '';
    this.sheetDefault = spec !== undefined ? spec.defaultValue : '';
    this.sheetInputKind = item.inputKind ?? 'text';
    this.sheetDraft = this.currentInputValue(key);
    this.sheetKind = 'input';
  }

  private sheetHintFor(key: string): string {
    if (key === 'vpnInterfaceAddress') {
      return this.t('settings.vpnInterfaceAddress.hint');
    }
    if (key === 'fragmentPackets') {
      return this.t('settings.fragmentPackets.hint');
    }
    const spec: SettingSelectSpec | undefined = findSelectSpec(key);
    return spec !== undefined && spec.hintKey.length > 0 ? this.t(spec.hintKey) : '';
  }

  private buildSheetOptions(key: string): SheetOptionVM[] {
    const result: SheetOptionVM[] = [];
    if (key === 'vpnInterfaceAddress') {
      for (let index = 0; index < VPN_INTERFACE_ADDRESS_CONFIGS.length; index++) {
        result.push({
          value: index.toString(),
          label: VPN_INTERFACE_ADDRESS_CONFIGS[index].displayName,
          desc: '',
          selected: index === this.settingVpnInterfaceAddressIndex
        });
      }
      return result;
    }
    if (key === 'fragmentPackets') {
      const current = normalizeClientCompatFragmentPackets(this.settingFragmentPackets);
      for (let index = 0; index < CLIENT_COMPAT_FRAGMENT_PACKET_OPTIONS.length; index++) {
        const value = CLIENT_COMPAT_FRAGMENT_PACKET_OPTIONS[index];
        result.push({ value: value, label: value, desc: '', selected: value === current });
      }
      return result;
    }
    const spec: SettingSelectSpec | undefined = findSelectSpec(key);
    if (spec === undefined) {
      return result;
    }
    const current = this.currentOptionValue(key);
    for (let index = 0; index < spec.choices.length; index++) {
      const choice = spec.choices[index];
      result.push({
        value: choice.value,
        label: this.t(choice.labelKey),
        desc: choice.descKey.length > 0 ? this.t(choice.descKey) : '',
        selected: choice.value === current
      });
    }
    return result;
  }

  private currentOptionValue(key: string): string {
    switch (key) {
      case 'mode': return this.settingMode;
      case 'coreType': return this.settingCoreType;
      case 'uiModeNight': return this.settingUiModeNight;
      case 'vpnBypassLan': return this.settingVpnBypassLan;
      case 'logLevel': return normalizeClientCompatCoreLogLevel(this.settingLogLevel);
      case 'hevTunLogLevel': return normalizeHevTunLogLevel(this.settingHevTunLogLevel);
      case 'outboundDomainResolveMethod': return this.settingOutboundDomainResolveMethod;
      case 'muxXudpQuic': return normalizeClientCompatMuxXudpQuic(this.settingMuxXudpQuic);
      default: return '';
    }
  }

  private applyOptionValue(key: string, value: string): void {
    switch (key) {
      case 'mode':
        this.settingMode = value;
        break;
      case 'coreType':
        this.settingCoreType = value;
        break;
      case 'uiModeNight':
        this.settingUiModeNight = value;
        break;
      case 'vpnBypassLan':
        this.settingVpnBypassLan = value;
        break;
      case 'logLevel':
        this.settingLogLevel = value;
        break;
      case 'hevTunLogLevel':
        this.settingHevTunLogLevel = value;
        break;
      case 'outboundDomainResolveMethod':
        this.settingOutboundDomainResolveMethod = value as OutboundDomainResolveMethod;
        break;
      case 'muxXudpQuic':
        this.settingMuxXudpQuic = value;
        break;
      case 'vpnInterfaceAddress':
        this.settingVpnInterfaceAddressIndex = Number(value);
        break;
      case 'fragmentPackets':
        this.settingFragmentPackets = value;
        break;
      default:
        break;
    }
  }

  private pickOption(value: string): void {
    const key = this.sheetKey;
    this.applyOptionValue(key, value);
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.sheetTitle));
    this.closeSheet();
    // 内核选择存在独立 store，不进 AppSettings 草稿。
    if (key === 'coreType') {
      this.persistCoreType(value);
      return;
    }
    this.persistSettings(false);
  }

  private async persistCoreType(value: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      this.settingCoreType = await CoreSelectionStore.save(context, value as CoreType);
    } catch (error) {
      this.lastError = this.f1('error.saveSettings', 'error', JSON.stringify(error));
    }
  }

  private commitInput(): void {
    const key = this.sheetKey;
    this.updateSettingInput(key, this.sheetDraft);
    this.closeSheet();
    this.persistSettings(false);
  }

  private resetInput(): void {
    this.sheetDraft = this.sheetDefault;
  }

  private closeSheet(): void {
    this.sheetKind = '';
  }

  private defaultRangeText(): string {
    const parts: string[] = [];
    if (this.sheetDefault.length > 0) {
      parts.push(this.t('settings.sheet.defaultPrefix') + ' ' + this.sheetDefault);
    }
    if (this.sheetRange.length > 0) {
      parts.push(this.sheetRange);
    }
    return parts.join(' · ');
  }

  private sheetInputType(): InputType {
    if (this.sheetInputKind === 'number') {
      return InputType.Number;
    }
    if (this.sheetInputKind === 'password') {
      return InputType.Password;
    }
    return InputType.Normal;
  }

  @Builder
  private SettingSheet() {
    if (this.sheetKind.length > 0) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppColor.scrim)
          .onClick(() => {
            this.closeSheet();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseOut }))

        Column() {
          Row()
            .width(38)
            .height(5)
            .borderRadius(Radius.pill)
            .backgroundColor(AppColor.border)
            .margin({ top: 9, bottom: Space.xs })

          Row({ space: Space.md }) {
            Column({ space: 2 }) {
              Text(this.sheetTitle)
                .fontSize(FontSz.headline)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColor.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.sheetHint.length > 0) {
                Text(this.sheetHint)
                  .fontSize(FontSz.footnote)
                  .fontColor(AppColor.textTertiary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Stack() {
              Text('✕')
                .fontSize(13)
                .fontColor(AppColor.textSecondary)
            }
            .width(30)
            .height(30)
            .borderRadius(Radius.pill)
            .backgroundColor(AppColor.surfaceAlt)
            .onClick(() => {
              this.closeSheet();
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: Space.lg, right: Space.lg, top: Space.xs, bottom: Space.md })

          if (this.sheetKind === 'select') {
            this.SheetSelectBody()
          } else if (this.sheetKind === 'input') {
            this.SheetInputBody()
          }
        }
        .width('100%')
        .backgroundColor(AppColor.surface)
        .borderRadius({ topLeft: 22, topRight: 22 })
        .padding({ bottom: Space.xl })
        .gesture(
          SwipeGesture({ direction: SwipeDirection.Vertical })
            .onAction((event: GestureEvent) => {
              if (event.angle > 45 && event.angle < 135) {
                this.closeSheet();
              }
            })
        )
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 480 }))
          .animation({ duration: 300, curve: Curve.FastOutSlowIn }))
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private SheetSelectBody() {
    Column({ space: Space.xs }) {
      ForEach(this.sheetOptions, (opt: SheetOptionVM) => {
        Row({ space: Space.md }) {
          Column({ space: 2 }) {
            Text(opt.label)
              .fontSize(FontSz.callout)
              .fontWeight(FontWeight.Medium)
              .fontColor(opt.selected ? AppColor.brand : AppColor.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (opt.desc.length > 0) {
              Text(opt.desc)
                .fontSize(FontSz.footnote)
                .fontColor(AppColor.textTertiary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (opt.selected) {
            Image($r('app.media.ic_check'))
              .width(22)
              .height(22)
              .fillColor(AppColor.brand)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 14, right: 14, top: Space.md, bottom: Space.md })
        .borderRadius(14)
        .backgroundColor(opt.selected ? AppColor.brandTint : Color.Transparent)
        .onClick(() => {
          this.pickOption(opt.value);
        })
      }, (opt: SheetOptionVM) => opt.value)
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md })
  }

  @Builder
  private SheetInputBody() {
    Column() {
      Row({ space: Space.sm }) {
        TextInput({ text: this.sheetDraft, placeholder: this.sheetTitle })
          .type(this.sheetInputType())
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .borderRadius(0)
          .fontSize(FontSz.title)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .placeholderColor(AppColor.textTertiary)
          .showPasswordIcon(this.sheetInputKind === 'password')
          .passwordIcon({
            onIconSrc: $r('app.media.ic_eye'),
            offIconSrc: $r('app.media.ic_eye_off')
          })
          .onChange((value: string) => {
            this.sheetDraft = value;
          })
        if (this.sheetUnit.length > 0) {
          Text(this.sheetUnit)
            .fontSize(FontSz.body)
            .fontColor(AppColor.textTertiary)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ bottom: Space.sm })
      .border({ width: { bottom: 2 }, color: { bottom: AppColor.brand } })

      if (this.sheetDefault.length > 0 || this.sheetRange.length > 0) {
        Row({ space: Space.sm }) {
          Text(this.defaultRangeText())
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.sheetDefault.length > 0) {
            Text(this.t('settings.sheet.restoreDefault'))
              .fontSize(FontSz.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColor.brand)
              .onClick(() => {
                this.resetInput();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: Space.md })
      }

      Button(this.t('settings.sheet.done'))
        .width('100%')
        .height(46)
        .backgroundColor(AppColor.brand)
        .fontColor(AppColor.onBrand)
        .fontSize(FontSz.callout)
        .fontWeight(FontWeight.Medium)
        .borderRadius(Radius.pill)
        .margin({ top: Space.lg })
        .onClick(() => {
          this.commitInput();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Space.lg, right: Space.lg })
  }

  private vpnInterfaceAddressLabel(): string {
    return resolveVpnInterfaceAddressConfig(this.settingVpnInterfaceAddressIndex).displayName;
  }

  private fragmentPacketsLabel(): string {
    return normalizeClientCompatFragmentPackets(this.settingFragmentPackets);
  }

  private isMuxXudpQuicAvailable(): boolean {
    const parsed = Number(this.settingMuxXudpConcurrency.trim());
    if (Number.isNaN(parsed)) {
      return true;
    }
    return Math.floor(parsed) >= 0;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
