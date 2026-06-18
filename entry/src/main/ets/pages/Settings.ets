import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { SectionHeader } from '../components/SectionHeader';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import {
  APP_MODE_PROXY_ONLY,
  APP_MODE_VPN,
  AppLanguage,
  DEFAULT_IP_API_URL,
  normalizeAppRuntimeMode,
  OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS,
  OUTBOUND_DOMAIN_RESOLVE_NONE,
  OUTBOUND_DOMAIN_RESOLVE_REPLACE,
  OutboundDomainResolveMethod,
  resolveVpnInterfaceAddressConfig,
  RoutingRule,
  UI_MODE_NIGHT_DARK,
  UI_MODE_NIGHT_LIGHT,
  UI_MODE_NIGHT_SYSTEM,
  VPN_BYPASS_LAN_BYPASS,
  VPN_BYPASS_LAN_FOLLOW_CONFIG,
  VPN_BYPASS_LAN_PROXY,
  VPN_INTERFACE_ADDRESS_CONFIGS
} from '../core/Profile';
import { applyColorMode } from '../core/ColorMode';
import {
  LanguageToggleRow,
  SettingInputRow,
  SettingToggleRow
} from '../features/settings/SettingsControls';
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

@Entry
@Component
struct SettingsPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private settingUiModeNight: string = UI_MODE_NIGHT_SYSTEM;
  @State private settingSpeedEnabled: boolean = false;
  @State private settingConfirmRemove: boolean = false;
  @State private settingStartScanImmediate: boolean = false;
  @State private settingStartOnBoot: boolean = false;
  @State private settingGroupAllDisplay: boolean = false;
  @State private settingDoubleColumnDisplay: boolean = false;
  @State private settingSniffing: boolean = true;
  @State private settingRouteOnly: boolean = false;
  @State private settingLocalDns: boolean = false;
  @State private settingFakeDns: boolean = false;
  @State private settingAppendHttpProxy: boolean = false;
  @State private settingLocalSocks: boolean = false;
  @State private settingLocalSocksPort: string = '10809';
  @State private settingLocalSocksDynamicPort: boolean = false;
  @State private settingLocalSocksUdp: boolean = true;
  @State private settingLocalSocksUsername: string = '';
  @State private settingLocalSocksPassword: string = '';
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
  @State private settingVpnMtu: string = '1400';
  @State private settingLogLevel: string = 'warning';
  @State private settingDelayTestUrl: string = 'https://www.gstatic.com/generate_204';
  @State private settingIpApiUrl: string = DEFAULT_IP_API_URL;
  @State private settingRealPingConcurrency: string = '16';
  @State private settingMode: string = APP_MODE_VPN;
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
  @State private perAppProxyBypass: boolean = true;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.settings.title'),
        showBack: true
      })

      Scroll() {
        Column({ space: Space.lg }) {
          // 界面
          SectionHeader({ title: this.t('settings.language.section') })
          Column() {
            this.LanguageToggle()
            this.RowDivider()
            this.SettingOption(this.t('settings.uiModeNight'), this.uiModeNightLabel(), 'uiModeNight')
            this.RowDivider()
            this.SettingToggle(this.t('settings.speedEnabled'), this.settingSpeedEnabled, 'speedEnabled')
            this.RowDivider()
            this.SettingToggle(this.t('settings.confirmRemove'), this.settingConfirmRemove, 'confirmRemove')
            this.RowDivider()
            this.SettingToggle(this.t('settings.startScanImmediate'), this.settingStartScanImmediate, 'startScanImmediate')
            this.RowDivider()
            this.SettingToggle(this.t('settings.startOnBoot'), this.settingStartOnBoot, 'startOnBoot')
            this.RowDivider()
            this.SettingToggle(this.t('settings.groupAllDisplay'), this.settingGroupAllDisplay, 'groupAllDisplay')
            this.RowDivider()
            this.SettingToggle(this.t('settings.doubleColumnDisplay'), this.settingDoubleColumnDisplay, 'doubleColumnDisplay')
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 核心
          SectionHeader({ title: this.t('settings.core'), detail: this.t('settings.core.detail') })
          Column() {
            this.SettingOption(this.t('settings.mode'), this.modeLabel(), 'mode')
            this.RowDivider()
            this.SettingToggle(this.t('settings.sniffing'), this.settingSniffing, 'sniffing')
            this.RowDivider()
            this.SettingToggle(this.t('settings.routeOnly'), this.settingRouteOnly, 'routeOnly')
            this.RowDivider()
            this.SettingToggle(this.t('settings.allowInsecure'), this.settingAllowInsecure, 'allowInsecure')
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // VPN
          SectionHeader({ title: this.t('settings.vpn'), detail: this.t('settings.vpn.detail') })
          Column() {
            this.SettingToggle(this.t('settings.perAppProxy'), this.settingPerAppProxy, 'perApp')
            this.RowDivider()
            this.SettingToggle(this.t('settings.localDns'), this.settingLocalDns, 'localDns')
            this.RowDivider()
            this.SettingToggle(this.t('settings.fakeDns'), this.settingFakeDns, 'fakeDns')
            this.RowDivider()
            this.SettingInput(this.t('settings.localDnsPort'), this.settingLocalDnsPort, 'localDnsPort')
            this.RowDivider()
            this.SettingToggle(this.t('settings.proxySharing'), this.settingProxySharing, 'proxySharing')
            this.RowDivider()
            this.SettingToggle(this.t('settings.appendHttpProxy'), this.settingAppendHttpProxy, 'appendHttpProxy')
            this.RowDivider()
            this.SettingToggle(this.t('settings.localSocks'), this.settingLocalSocks, 'localSocks')
            this.RowDivider()
            this.SettingInput(this.t('settings.localSocksPort'), this.settingLocalSocksPort, 'localSocksPort')
            this.RowDivider()
            this.SettingToggle(this.t('settings.localSocksDynamicPort'), this.settingLocalSocksDynamicPort, 'localSocksDynamicPort')
            this.RowDivider()
            this.SettingToggle(this.t('settings.localSocksUdp'), this.settingLocalSocksUdp, 'localSocksUdp')
            this.RowDivider()
            this.SettingInput(this.t('settings.localSocksUsername'), this.settingLocalSocksUsername, 'localSocksUsername')
            this.RowDivider()
            this.SettingInput(this.t('settings.localSocksPassword'), this.settingLocalSocksPassword, 'localSocksPassword')
            this.RowDivider()
            this.SettingToggle(this.t('settings.ipv6Enabled'), this.settingIpv6Enabled, 'ipv6Enabled')
            this.RowDivider()
            this.SettingToggle(this.t('settings.preferIpv6'), this.settingPreferIpv6, 'preferIpv6')
            this.RowDivider()
            this.SettingOption(this.t('settings.vpnBypassLan'), this.vpnBypassLanLabel(), 'vpnBypassLan')
            this.RowDivider()
            this.SettingOption(this.t('settings.vpnInterfaceAddress'), this.vpnInterfaceAddressLabel(), 'vpnInterfaceAddress')
            this.RowDivider()
            this.SettingInput(this.t('settings.vpnDns'), this.settingVpnDns, 'vpnDns')
            this.RowDivider()
            this.SettingInput(this.t('settings.vpnMtu'), this.settingVpnMtu, 'vpnMtu')
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 传输
          SectionHeader({ title: this.t('settings.transport'), detail: this.t('settings.transport.detail') })
          Column() {
            this.SettingToggle(this.t('settings.mux'), this.settingMux, 'mux')
            if (this.settingMux) {
              this.RowDivider()
              this.SettingInput(this.t('settings.muxConcurrency'), this.settingMuxConcurrency, 'muxConcurrency')
              this.RowDivider()
              this.SettingInput(this.t('settings.muxXudpConcurrency'), this.settingMuxXudpConcurrency, 'muxXudpConcurrency')
              this.RowDivider()
              this.SettingOption(this.t('settings.muxXudpQuic'), this.muxXudpQuicLabel(), 'muxXudpQuic')
            }
            this.RowDivider()
            this.SettingToggle(this.t('settings.fragment'), this.settingFragment, 'fragment')
            if (this.settingFragment) {
              this.RowDivider()
              this.SettingInput(this.t('settings.fragmentPackets'), this.settingFragmentPackets, 'fragmentPackets')
              this.RowDivider()
              this.SettingInput(this.t('settings.fragmentLength'), this.settingFragmentLength, 'fragmentLength')
              this.RowDivider()
              this.SettingInput(this.t('settings.fragmentInterval'), this.settingFragmentInterval, 'fragmentInterval')
            }
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 进阶
          SectionHeader({ title: this.t('settings.advanced'), detail: this.t('settings.advanced.detail') })
          Column() {
            this.SettingInput(this.t('settings.remoteDns'), this.settingRemoteDns, 'remoteDns')
            this.RowDivider()
            this.SettingInput(this.t('settings.domesticDns'), this.settingDomesticDns, 'domesticDns')
            this.RowDivider()
            this.SettingInput(this.t('settings.dnsHosts'), this.settingDnsHosts, 'dnsHosts')
            this.RowDivider()
            this.SettingOption(this.t('settings.outboundDomainResolveMethod'), this.outboundDomainResolveMethodLabel(), 'outboundDomainResolveMethod')
            this.RowDivider()
            this.SettingInput(this.t('settings.delayTestUrl'), this.settingDelayTestUrl, 'delayTestUrl')
            this.RowDivider()
            this.SettingInput(this.t('settings.ipApiUrl'), this.settingIpApiUrl, 'ipApiUrl')
            this.RowDivider()
            this.SettingOption(this.t('settings.logLevel'), this.logLevelLabel(), 'logLevel')
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 节点测速
          SectionHeader({ title: this.t('settings.testing') })
          Column() {
            this.SettingInput(this.t('settings.realPingConcurrency'), this.settingRealPingConcurrency, 'realPingConcurrency')
            this.RowDivider()
            this.SettingToggle(this.t('settings.autoSortAfterTest'), this.settingAutoSortAfterTest, 'autoSortAfterTest')
            this.RowDivider()
            this.SettingToggle(this.t('settings.autoRemoveAfterTest'), this.settingAutoRemoveAfterTest, 'autoRemoveAfterTest')
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

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

          Button(this.t('action.saveSettings'))
            .height(46)
            .width('100%')
            .backgroundColor(AppColor.brand)
            .fontColor(AppColor.onBrand)
            .fontWeight(FontWeight.Medium)
            .borderRadius(Radius.pill)
            .margin({ left: Space.lg, right: Space.lg, top: Space.sm })
            .onClick(() => {
              this.persistSettings(true);
            })
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
  private LanguageToggle() {
    LanguageToggleRow({
      title: this.t('settings.language.title'),
      zhLabel: this.t('settings.language.zh'),
      enLabel: this.t('settings.language.en'),
      language: this.language,
      onChange: (nextLanguage: AppLanguage) => {
        this.changeLanguage(nextLanguage);
      }
    })
  }

  @Builder
  private SettingToggle(title: string, enabled: boolean, action: string) {
    SettingToggleRow({
      title,
      settingKey: '',
      isEnabled: enabled,
      action,
      onLabel: this.t('action.on'),
      offLabel: this.t('action.off'),
      onToggle: (nextAction: string) => {
        this.toggleSetting(nextAction);
      }
    })
  }

  @Builder
  private SettingInput(title: string, value: string, action: string) {
    SettingInputRow({
      title,
      settingKey: '',
      value,
      action,
      onChange: (nextAction: string, nextValue: string) => {
        this.updateSettingInput(nextAction, nextValue);
      }
    })
  }

  @Builder
  private SettingOption(title: string, value: string, action: string) {
    Row({ space: Space.md }) {
      Text(title)
        .fontSize(FontSz.callout)
        .fontColor(AppColor.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(value)
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textSecondary)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(54)
    .padding({ left: Space.lg, right: Space.lg })
    .backgroundColor(AppColor.surface)
    .onClick(() => {
      this.showSettingOptionMenu(action);
    })
  }

  private async loadState(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.applyDraft(SETTINGS_CONTROLLER.toDraft(await SETTINGS_CONTROLLER.load(context)));
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
        break;
      case 'fakeDns':
        this.settingFakeDns = !this.settingFakeDns;
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
        this.settingProxySharing = !this.settingProxySharing;
        break;
      case 'appendHttpProxy':
        this.settingAppendHttpProxy = !this.settingAppendHttpProxy;
        break;
      case 'localSocks':
        this.settingLocalSocks = !this.settingLocalSocks;
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
      const context = getContext(this) as common.Context;
      const saved = await SETTINGS_CONTROLLER.save(context, this.buildDraft());
      applyColorMode(context, saved.uiModeNight);
      this.applyDraft(SETTINGS_CONTROLLER.toDraft(saved));
      if (showMessage) {
        SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.settingsSaved'));
      }
      this.lastError = '';
    } catch (error) {
      this.lastError = this.f1('error.saveSettings', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    }
  }

  private async changeLanguage(language: AppLanguage): Promise<void> {
    if (this.language === language) {
      return;
    }
    this.language = language;
    await this.persistSettings(false);
    const label = this.language === 'zh' ? this.t('settings.language.zh') : this.t('settings.language.en');
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.languageChanged', 'language', label));
  }

  private buildDraft(): SettingsDraft {
    return {
      language: this.language,
      uiModeNight: this.settingUiModeNight,
      speedEnabled: this.settingSpeedEnabled,
      confirmRemove: this.settingConfirmRemove,
      startScanImmediate: this.settingStartScanImmediate,
      startOnBoot: this.settingStartOnBoot,
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
    this.settingGroupAllDisplay = draft.groupAllDisplay;
    this.settingDoubleColumnDisplay = draft.doubleColumnDisplay;
    this.settingSniffing = draft.sniffingEnabled;
    this.settingRouteOnly = draft.routeOnlyEnabled;
    this.settingPerAppProxy = draft.perAppProxyEnabled;
    this.perAppProxyList = draft.perAppProxyList ?? [];
    this.perAppProxyBypass = draft.perAppProxyBypass ?? true;
    this.settingLocalDns = draft.localDnsEnabled;
    this.settingFakeDns = draft.fakeDnsEnabled;
    this.settingAppendHttpProxy = draft.appendHttpProxy;
    this.settingLocalSocks = draft.localSocksEnabled;
    this.settingLocalSocksPort = draft.localSocksPort;
    this.settingLocalSocksDynamicPort = draft.localSocksDynamicPort;
    this.settingLocalSocksUdp = draft.localSocksUdpEnabled;
    this.settingLocalSocksUsername = draft.localSocksUsername;
    this.settingLocalSocksPassword = draft.localSocksPassword;
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

  private showSettingOptionMenu(action: string): void {
    if (action === 'vpnBypassLan') {
      this.showVpnBypassLanMenu();
      return;
    }
    if (action === 'uiModeNight') {
      this.showUiModeNightMenu();
      return;
    }
    if (action === 'mode') {
      this.showModeMenu();
      return;
    }
    if (action === 'vpnInterfaceAddress') {
      this.showVpnInterfaceAddressMenu();
      return;
    }
    if (action === 'logLevel') {
      this.showLogLevelMenu();
      return;
    }
    if (action === 'outboundDomainResolveMethod') {
      this.showOutboundDomainResolveMethodMenu();
      return;
    }
    if (action === 'muxXudpQuic') {
      this.showMuxXudpQuicMenu();
    }
  }

  private showVpnBypassLanMenu(): void {
    const values: string[] = [VPN_BYPASS_LAN_FOLLOW_CONFIG, VPN_BYPASS_LAN_BYPASS, VPN_BYPASS_LAN_PROXY];
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [
      { text: this.t('settings.vpnBypassLan.followConfig'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.vpnBypassLan.bypass'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.vpnBypassLan.proxy'), color: AppColor.brand } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: this.t('settings.vpnBypassLan'),
      buttons
    }).then((result) => {
      if (result.index >= 0 && result.index < values.length) {
        this.settingVpnBypassLan = values[result.index];
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.t('settings.vpnBypassLan')));
        this.persistSettings(false);
      }
    });
  }

  private showUiModeNightMenu(): void {
    const values: string[] = [UI_MODE_NIGHT_SYSTEM, UI_MODE_NIGHT_LIGHT, UI_MODE_NIGHT_DARK];
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [
      { text: this.t('settings.uiModeNight.system'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.uiModeNight.light'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.uiModeNight.dark'), color: AppColor.brand } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: this.t('settings.uiModeNight'),
      buttons
    }).then((result) => {
      if (result.index >= 0 && result.index < values.length) {
        this.settingUiModeNight = values[result.index];
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.t('settings.uiModeNight')));
        this.persistSettings(false);
      }
    });
  }

  private showModeMenu(): void {
    const values: string[] = [APP_MODE_VPN, APP_MODE_PROXY_ONLY];
    const buttons: [promptAction.Button, promptAction.Button] = [
      { text: this.t('settings.mode.vpn'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.mode.proxyOnly'), color: AppColor.brand } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: this.t('settings.mode'),
      buttons
    }).then((result) => {
      if (result.index >= 0 && result.index < values.length) {
        this.settingMode = values[result.index];
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.t('settings.mode')));
        this.persistSettings(false);
      }
    });
  }

  private showVpnInterfaceAddressMenu(startIndex: number = 0): void {
    const buttons = new Array<promptAction.Button>();
    const actions = new Array<number>();
    const hasPrevious = startIndex > 0;
    let itemLimit = 6 - (hasPrevious ? 1 : 0);
    if (startIndex + itemLimit < VPN_INTERFACE_ADDRESS_CONFIGS.length) {
      itemLimit -= 1;
    }
    const endIndex = Math.min(VPN_INTERFACE_ADDRESS_CONFIGS.length, startIndex + itemLimit);
    for (let index = startIndex; index < endIndex; index++) {
      buttons.push({ text: VPN_INTERFACE_ADDRESS_CONFIGS[index].displayName, color: AppColor.brand } as promptAction.Button);
      actions.push(index);
    }
    if (endIndex < VPN_INTERFACE_ADDRESS_CONFIGS.length) {
      buttons.push({ text: this.t('action.more'), color: AppColor.brand } as promptAction.Button);
      actions.push(-2);
    }
    if (hasPrevious) {
      buttons.push({ text: this.t('action.previous'), color: AppColor.textSecondary } as promptAction.Button);
      actions.push(-1);
    }
    promptAction.showActionMenu({
      title: this.t('settings.vpnInterfaceAddress'),
      buttons: this.toActionMenuButtons(buttons)
    }).then((result) => {
      if (result.index < 0 || result.index >= actions.length) {
        return;
      }
      const actionIndex = actions[result.index];
      if (actionIndex === -2) {
        this.showVpnInterfaceAddressMenu(endIndex);
        return;
      }
      if (actionIndex === -1) {
        this.showVpnInterfaceAddressMenu(Math.max(0, startIndex - 5));
        return;
      }
      if (actionIndex >= 0 && actionIndex < VPN_INTERFACE_ADDRESS_CONFIGS.length) {
        this.settingVpnInterfaceAddressIndex = actionIndex;
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.t('settings.vpnInterfaceAddress')));
        this.persistSettings(false);
      }
    });
  }

  private showLogLevelMenu(): void {
    const values: string[] = ['debug', 'info', 'warning', 'error', 'none'];
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button, promptAction.Button, promptAction.Button] = [
      { text: this.t('settings.logLevel.debug'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.logLevel.info'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.logLevel.warning'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.logLevel.error'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.logLevel.none'), color: AppColor.brand } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: this.t('settings.logLevel'),
      buttons
    }).then((result) => {
      if (result.index >= 0 && result.index < values.length) {
        this.settingLogLevel = values[result.index];
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.t('settings.logLevel')));
        this.persistSettings(false);
      }
    });
  }

  private showOutboundDomainResolveMethodMenu(): void {
    const values: OutboundDomainResolveMethod[] = [
      OUTBOUND_DOMAIN_RESOLVE_NONE,
      OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS,
      OUTBOUND_DOMAIN_RESOLVE_REPLACE
    ];
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [
      { text: this.t('settings.outboundDomainResolveMethod.none'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.outboundDomainResolveMethod.dnsHosts'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.outboundDomainResolveMethod.replace'), color: AppColor.brand } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: this.t('settings.outboundDomainResolveMethod'),
      buttons
    }).then((result) => {
      if (result.index >= 0 && result.index < values.length) {
        this.settingOutboundDomainResolveMethod = values[result.index];
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.t('settings.outboundDomainResolveMethod')));
        this.persistSettings(false);
      }
    });
  }

  private showMuxXudpQuicMenu(): void {
    const values: string[] = ['reject', 'allow', 'skip'];
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [
      { text: this.t('settings.muxXudpQuic.reject'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.muxXudpQuic.allow'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('settings.muxXudpQuic.skip'), color: AppColor.brand } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: this.t('settings.muxXudpQuic'),
      buttons
    }).then((result) => {
      if (result.index >= 0 && result.index < values.length) {
        this.settingMuxXudpQuic = values[result.index];
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', this.t('settings.muxXudpQuic')));
        this.persistSettings(false);
      }
    });
  }

  private toActionMenuButtons(buttons: Array<promptAction.Button>): [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] {
    return buttons as [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?];
  }

  private vpnInterfaceAddressLabel(): string {
    return resolveVpnInterfaceAddressConfig(this.settingVpnInterfaceAddressIndex).displayName;
  }

  private vpnBypassLanLabel(): string {
    if (this.settingVpnBypassLan === VPN_BYPASS_LAN_FOLLOW_CONFIG) {
      return this.t('settings.vpnBypassLan.followConfig');
    }
    if (this.settingVpnBypassLan === VPN_BYPASS_LAN_PROXY) {
      return this.t('settings.vpnBypassLan.proxy');
    }
    return this.t('settings.vpnBypassLan.bypass');
  }

  private uiModeNightLabel(): string {
    if (this.settingUiModeNight === UI_MODE_NIGHT_LIGHT) {
      return this.t('settings.uiModeNight.light');
    }
    if (this.settingUiModeNight === UI_MODE_NIGHT_DARK) {
      return this.t('settings.uiModeNight.dark');
    }
    return this.t('settings.uiModeNight.system');
  }

  private modeLabel(): string {
    if (this.settingMode === APP_MODE_PROXY_ONLY) {
      return this.t('settings.mode.proxyOnly');
    }
    return this.t('settings.mode.vpn');
  }

  private logLevelLabel(): string {
    if (this.settingLogLevel === 'debug') {
      return this.t('settings.logLevel.debug');
    }
    if (this.settingLogLevel === 'info') {
      return this.t('settings.logLevel.info');
    }
    if (this.settingLogLevel === 'error') {
      return this.t('settings.logLevel.error');
    }
    if (this.settingLogLevel === 'none') {
      return this.t('settings.logLevel.none');
    }
    return this.t('settings.logLevel.warning');
  }

  private outboundDomainResolveMethodLabel(): string {
    if (this.settingOutboundDomainResolveMethod === OUTBOUND_DOMAIN_RESOLVE_NONE) {
      return this.t('settings.outboundDomainResolveMethod.none');
    }
    if (this.settingOutboundDomainResolveMethod === OUTBOUND_DOMAIN_RESOLVE_REPLACE) {
      return this.t('settings.outboundDomainResolveMethod.replace');
    }
    return this.t('settings.outboundDomainResolveMethod.dnsHosts');
  }

  private muxXudpQuicLabel(): string {
    if (this.settingMuxXudpQuic === 'allow') {
      return this.t('settings.muxXudpQuic.allow');
    }
    if (this.settingMuxXudpQuic === 'skip') {
      return this.t('settings.muxXudpQuic.skip');
    }
    return this.t('settings.muxXudpQuic.reject');
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
