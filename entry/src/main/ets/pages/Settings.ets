import { common } from '@kit.AbilityKit';
import { SectionHeader } from '../components/SectionHeader';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import {
  LanguageToggleRow,
  SettingInputRow,
  SettingToggleRow
} from '../features/settings/SettingsControls';
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct SettingsPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private settingSniffing: boolean = true;
  @State private settingRouteOnly: boolean = false;
  @State private settingLocalDns: boolean = false;
  @State private settingFakeDns: boolean = false;
  @State private settingMux: boolean = false;
  @State private settingFragment: boolean = false;
  @State private settingProxySharing: boolean = false;
  @State private settingAllowInsecure: boolean = false;
  @State private settingPerAppProxy: boolean = false;
  @State private settingSocksPort: string = '10808';
  @State private settingRemoteDns: string = '1.1.1.1';
  @State private settingDomesticDns: string = '223.5.5.5';
  @State private settingVpnDns: string = '1.1.1.1';
  @State private settingLogLevel: string = 'warning';
  @State private settingDelayTestUrl: string = 'https://www.gstatic.com/generate_204';
  @State private trafficMode: string = 'rules';
  @State private routingStrategy: string = 'AsIs';
  @State private lastError: string = '';

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.settings.title'),
        summary: this.t('settings.advanced.detail'),
        showBack: true
      })
      Scroll() {
        Column({ space: 0 }) {
          SectionHeader({ title: this.t('settings.language.section'), detail: this.t('settings.language.detail') })
          this.LanguageToggle()
          SectionHeader({ title: this.t('settings.core'), detail: this.t('settings.core.detail') })
          this.SettingToggle(this.t('settings.sniffing'), 'pref_sniffing_enabled', this.settingSniffing, 'sniffing')
          this.SettingToggle(this.t('settings.routeOnly'), 'pref_route_only_enabled', this.settingRouteOnly, 'routeOnly')
          this.SettingToggle(this.t('settings.allowInsecure'), 'pref_allow_insecure', this.settingAllowInsecure, 'allowInsecure')
          SectionHeader({ title: this.t('settings.vpn'), detail: this.t('settings.vpn.detail') })
          this.SettingToggle(this.t('settings.perAppProxy'), 'pref_per_app_proxy', this.settingPerAppProxy, 'perApp')
          this.SettingToggle(this.t('settings.localDns'), 'pref_local_dns_enabled', this.settingLocalDns, 'localDns')
          this.SettingToggle(this.t('settings.fakeDns'), 'pref_fake_dns_enabled', this.settingFakeDns, 'fakeDns')
          this.SettingToggle(this.t('settings.proxySharing'), 'pref_proxy_sharing_enabled', this.settingProxySharing, 'proxySharing')
          this.SettingInput(this.t('settings.socksPort'), 'pref_socks_port', this.settingSocksPort, 'socksPort')
          this.SettingInput(this.t('settings.vpnDns'), 'pref_vpn_dns', this.settingVpnDns, 'vpnDns')
          SectionHeader({ title: this.t('settings.transport'), detail: this.t('settings.transport.detail') })
          this.SettingToggle(this.t('settings.mux'), 'pref_mux_enabled', this.settingMux, 'mux')
          this.SettingToggle(this.t('settings.fragment'), 'pref_fragment_enabled', this.settingFragment, 'fragment')
          SectionHeader({ title: this.t('settings.advanced'), detail: this.t('settings.advanced.detail') })
          this.SettingInput(this.t('settings.remoteDns'), 'pref_remote_dns', this.settingRemoteDns, 'remoteDns')
          this.SettingInput(this.t('settings.domesticDns'), 'pref_domestic_dns', this.settingDomesticDns, 'domesticDns')
          this.SettingInput(this.t('settings.delayTestUrl'), 'pref_delay_test_url', this.settingDelayTestUrl, 'delayTestUrl')
          this.SettingInput(this.t('settings.logLevel'), 'pref_core_loglevel', this.settingLogLevel, 'logLevel')

          if (this.lastError.length > 0) {
            Text(this.lastError)
              .fontSize(12)
              .fontColor('#B42318')
              .width('100%')
              .padding(10)
              .backgroundColor('#FEF3F2')
              .borderRadius(6)
          }

          Button(this.t('action.saveSettings'))
            .height(40)
            .width('88%')
            .backgroundColor('#1C1B1F')
            .fontColor('#FFFFFF')
            .borderRadius(20)
            .margin({ top: 18, bottom: 10 })
            .onClick(() => {
              this.persistSettings(true);
            })
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private LanguageToggle() {
    LanguageToggleRow({
      title: this.t('settings.language.title'),
      settingKey: this.t('settings.language.key'),
      zhLabel: this.t('settings.language.zh'),
      enLabel: this.t('settings.language.en'),
      language: this.language,
      onChange: (nextLanguage: AppLanguage) => {
        this.changeLanguage(nextLanguage);
      }
    })
  }

  @Builder
  private SettingToggle(title: string, key: string, enabled: boolean, action: string) {
    SettingToggleRow({
      title,
      settingKey: key,
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
  private SettingInput(title: string, key: string, value: string, action: string) {
    SettingInputRow({
      title,
      settingKey: key,
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
      case 'proxySharing':
        this.settingProxySharing = !this.settingProxySharing;
        break;
      case 'allowInsecure':
        this.settingAllowInsecure = !this.settingAllowInsecure;
        break;
      case 'perApp':
        this.settingPerAppProxy = !this.settingPerAppProxy;
        break;
      default:
        break;
    }
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.settingsChanged', 'action', action));
    this.persistSettings(false);
  }

  private updateSettingInput(action: string, value: string): void {
    switch (action) {
      case 'socksPort':
        this.settingSocksPort = value;
        break;
      case 'vpnDns':
        this.settingVpnDns = value;
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
      localDnsEnabled: this.settingLocalDns,
      fakeDnsEnabled: this.settingFakeDns,
      muxEnabled: this.settingMux,
      fragmentEnabled: this.settingFragment,
      proxySharingEnabled: this.settingProxySharing,
      allowInsecure: this.settingAllowInsecure,
      socksPort: this.settingSocksPort,
      remoteDns: this.settingRemoteDns,
      domesticDns: this.settingDomesticDns,
      vpnDns: this.settingVpnDns,
      logLevel: this.settingLogLevel,
      delayTestUrl: this.settingDelayTestUrl,
      trafficMode: this.trafficMode,
      routingDomainStrategy: this.routingStrategy
    };
  }

  private applyDraft(draft: SettingsDraft): void {
    this.language = draft.language;
    this.settingSniffing = draft.sniffingEnabled;
    this.settingRouteOnly = draft.routeOnlyEnabled;
    this.settingPerAppProxy = draft.perAppProxyEnabled;
    this.settingLocalDns = draft.localDnsEnabled;
    this.settingFakeDns = draft.fakeDnsEnabled;
    this.settingMux = draft.muxEnabled;
    this.settingFragment = draft.fragmentEnabled;
    this.settingProxySharing = draft.proxySharingEnabled;
    this.settingAllowInsecure = draft.allowInsecure;
    this.settingSocksPort = draft.socksPort;
    this.settingRemoteDns = draft.remoteDns;
    this.settingDomesticDns = draft.domesticDns;
    this.settingVpnDns = draft.vpnDns;
    this.settingLogLevel = draft.logLevel;
    this.settingDelayTestUrl = draft.delayTestUrl;
    this.trafficMode = draft.trafficMode;
    this.routingStrategy = draft.routingDomainStrategy;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
