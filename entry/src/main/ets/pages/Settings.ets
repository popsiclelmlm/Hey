import { common } from '@kit.AbilityKit';
import { SectionHeader } from '../components/SectionHeader';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, RoutingRule } from '../core/Profile';
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
  @State private settingSniffing: boolean = true;
  @State private settingRouteOnly: boolean = false;
  @State private settingLocalDns: boolean = false;
  @State private settingFakeDns: boolean = false;
  @State private settingAppendHttpProxy: boolean = false;
  @State private settingMux: boolean = false;
  @State private settingFragment: boolean = false;
  @State private settingPreferIpv6: boolean = false;
  @State private settingProxySharing: boolean = false;
  @State private settingAllowInsecure: boolean = false;
  @State private settingPerAppProxy: boolean = false;
  @State private settingRemoteDns: string = '1.1.1.1';
  @State private settingDomesticDns: string = '223.5.5.5';
  @State private settingVpnDns: string = '1.1.1.1';
  @State private settingVpnMtu: string = '1400';
  @State private settingLogLevel: string = 'warning';
  @State private settingDelayTestUrl: string = 'https://www.gstatic.com/generate_204';
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
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 核心
          SectionHeader({ title: this.t('settings.core'), detail: this.t('settings.core.detail') })
          Column() {
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
            this.SettingToggle(this.t('settings.proxySharing'), this.settingProxySharing, 'proxySharing')
            this.RowDivider()
            this.SettingToggle(this.t('settings.appendHttpProxy'), this.settingAppendHttpProxy, 'appendHttpProxy')
            this.RowDivider()
            this.SettingToggle(this.t('settings.preferIpv6'), this.settingPreferIpv6, 'preferIpv6')
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
            this.RowDivider()
            this.SettingToggle(this.t('settings.fragment'), this.settingFragment, 'fragment')
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
            this.SettingInput(this.t('settings.delayTestUrl'), this.settingDelayTestUrl, 'delayTestUrl')
            this.RowDivider()
            this.SettingInput(this.t('settings.logLevel'), this.settingLogLevel, 'logLevel')
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          // 节点测速
          SectionHeader({ title: this.t('settings.testing') })
          Column() {
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
      case 'preferIpv6':
        this.settingPreferIpv6 = !this.settingPreferIpv6;
        break;
      case 'proxySharing':
        this.settingProxySharing = !this.settingProxySharing;
        break;
      case 'appendHttpProxy':
        this.settingAppendHttpProxy = !this.settingAppendHttpProxy;
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
      case 'remoteDns':
        this.settingRemoteDns = value;
        break;
      case 'domesticDns':
        this.settingDomesticDns = value;
        break;
      case 'delayTestUrl':
        this.settingDelayTestUrl = value;
        break;
      case 'logLevel':
        this.settingLogLevel = value;
        break;
      default:
        break;
    }
  }

  private async persistSettings(showMessage: boolean): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const saved = await SETTINGS_CONTROLLER.save(context, this.buildDraft());
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
      sniffingEnabled: this.settingSniffing,
      routeOnlyEnabled: this.settingRouteOnly,
      perAppProxyEnabled: this.settingPerAppProxy,
      perAppProxyList: this.perAppProxyList,
      perAppProxyBypass: this.perAppProxyBypass,
      localDnsEnabled: this.settingLocalDns,
      fakeDnsEnabled: this.settingFakeDns,
      appendHttpProxy: this.settingAppendHttpProxy,
      muxEnabled: this.settingMux,
      fragmentEnabled: this.settingFragment,
      preferIpv6: this.settingPreferIpv6,
      proxySharingEnabled: this.settingProxySharing,
      allowInsecure: this.settingAllowInsecure,
      remoteDns: this.settingRemoteDns,
      domesticDns: this.settingDomesticDns,
      vpnMtu: this.settingVpnMtu,
      vpnDns: this.settingVpnDns,
      logLevel: this.settingLogLevel,
      delayTestUrl: this.settingDelayTestUrl,
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
    this.settingSniffing = draft.sniffingEnabled;
    this.settingRouteOnly = draft.routeOnlyEnabled;
    this.settingPerAppProxy = draft.perAppProxyEnabled;
    this.perAppProxyList = draft.perAppProxyList ?? [];
    this.perAppProxyBypass = draft.perAppProxyBypass ?? true;
    this.settingLocalDns = draft.localDnsEnabled;
    this.settingFakeDns = draft.fakeDnsEnabled;
    this.settingAppendHttpProxy = draft.appendHttpProxy;
    this.settingMux = draft.muxEnabled;
    this.settingFragment = draft.fragmentEnabled;
    this.settingPreferIpv6 = draft.preferIpv6;
    this.settingProxySharing = draft.proxySharingEnabled;
    this.settingAllowInsecure = draft.allowInsecure;
    this.settingRemoteDns = draft.remoteDns;
    this.settingDomesticDns = draft.domesticDns;
    this.settingVpnMtu = draft.vpnMtu;
    this.settingVpnDns = draft.vpnDns;
    this.settingLogLevel = draft.logLevel;
    this.settingDelayTestUrl = draft.delayTestUrl;
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

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
