import { common } from '@kit.AbilityKit';
import { SectionHeader } from '../components/SectionHeader';
import { DEFAULT_LANGUAGE, normalizeLanguage, translate } from '../core/I18n';
import { AppLanguage, AppSettings, ConnectionStatus, ProxyNode, ProxyProfile, RuntimeStats, SubscriptionGroup, SubscriptionProfile } from '../core/Profile';
import { normalizeOutboundInput } from '../core/XrayConfig';
import { RuntimeStatusPanel } from '../features/runtime/RuntimePanel';
import { ConnectionController, ConnectionSnapshot } from '../services/ConnectionController';
import { DelayTester, DelayTestResult } from '../services/DelayTester';
import { DiagnosticEvent, DiagnosticLog } from '../services/DiagnosticLog';
import { SubscriptionManager, SubscriptionUpdateResult } from '../services/SubscriptionManager';
import { ProfileStore } from '../storage/ProfileStore';
import { DEFAULT_APP_SETTINGS, SettingsStore } from '../storage/SettingsStore';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { AppNavigationRail } from '../shell/AppNavigationRail';
import { AppTopBar } from '../shell/AppTopBar';
import { AppScreen, SCREEN_ENTRIES } from '../shell/AppScreen';
import {
  connectionStatusBackground,
  connectionStatusColor,
  formatBytes,
  formatClockTime,
  formatDuration
} from '../utils/Formatters';
import {
  formatOne,
  formatTwo,
  localizedConnectionStatus,
  localizedProfileSavedText,
  localizedSubscriptionStatusText,
  localizeCoreMessage
} from '../utils/LocalizationPresenter';

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
  private controller: ConnectionController = new ConnectionController();
  private timerId: number = -1;

  @State private outboundJson: string = '';
  @State private status: ConnectionStatus = ConnectionStatus.IDLE;
  @State private startedAt: number = 0;
  @State private elapsedText: string = '00:00';
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private validationMessage: string = translate(DEFAULT_LANGUAGE, 'validation.initial');
  @State private validationOk: boolean = false;
  @State private lastError: string = '';
  @State private logs: Array<string> = [translate(DEFAULT_LANGUAGE, 'log.ready')];
  @State private diagnosticLogs: Array<string> = [];
  @State private stats: RuntimeStats = EMPTY_STATS;
  @State private profileUpdatedAt: string = translate(DEFAULT_LANGUAGE, 'profile.notSaved');
  @State private profileUpdatedAtValue: number = 0;
  @State private subscriptionUrl: string = '';
  @State private nodes: Array<ProxyNode> = [];
  @State private selectedNodeId: string = '';
  @State private subscriptionMessage: string = translate(DEFAULT_LANGUAGE, 'subscription.none');
  @State private subscriptionUpdatedAt: number = 0;
  @State private subscriptionUpdating: boolean = false;
  @State private subscriptionGroups: Array<SubscriptionGroup> = [];
  @State private selectedGroupId: string = '';
  @State private activeScreen: AppScreen = AppScreen.SERVERS;
  @State private searchQuery: string = '';
  @State private importBuffer: string = '';
  @State private selectedImportProtocol: string = 'vless';
  @State private routingStrategy: string = 'AsIs';
  @State private trafficMode: string = DEFAULT_APP_SETTINGS.trafficMode;
  @State private delayTesting: boolean = false;
  @State private settingSniffing: boolean = true;
  @State private settingRouteOnly: boolean = false;
  @State private settingLocalDns: boolean = false;
  @State private settingFakeDns: boolean = false;
  @State private settingMux: boolean = false;
  @State private settingFragment: boolean = false;
  @State private settingProxySharing: boolean = false;
  @State private settingAllowInsecure: boolean = false;
  @State private settingPerAppProxy: boolean = false;
  @State private settingSocksPort: string = DEFAULT_APP_SETTINGS.socksPort.toString();
  @State private settingRemoteDns: string = DEFAULT_APP_SETTINGS.remoteDns;
  @State private settingDomesticDns: string = DEFAULT_APP_SETTINGS.domesticDns;
  @State private settingVpnDns: string = DEFAULT_APP_SETTINGS.vpnDns;
  @State private settingLogLevel: string = DEFAULT_APP_SETTINGS.logLevel;
  @State private settingDelayTestUrl: string = DEFAULT_APP_SETTINGS.delayTestUrl;
  private diagnosticRefreshing: boolean = false;

  aboutToAppear(): void {
    this.loadInitialState();
    this.timerId = setInterval(() => {
      this.refreshRuntime();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Row() {
      AppNavigationRail({
        activeScreen: $activeScreen,
        entries: SCREEN_ENTRIES,
        language: this.language,
        brand: 'Hey'
      })
      Column() {
        AppTopBar({
          title: this.activeScreenTitle(),
          summary: this.f2('topbar.summary', 'nodes', this.nodes.length.toString(), 'status', this.statusLabel()),
          statusLabel: this.statusLabel(),
          statusColor: this.statusColor(),
          statusBackground: this.statusBackground()
        })
        Scroll() {
          Column({ space: 14 }) {
            this.ActivePage()
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .height('100%')
      .layoutWeight(1)
      .backgroundColor('#F6F8FA')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F6F8FA')
  }

  @Builder
  private ActivePage() {
    if (this.activeScreen === AppScreen.SERVERS) {
      this.ServersPage()
    } else if (this.activeScreen === AppScreen.IMPORT) {
      this.ImportPage()
    } else if (this.activeScreen === AppScreen.SUBSCRIPTIONS) {
      this.SubscriptionsPage()
    } else if (this.activeScreen === AppScreen.ROUTING) {
      this.RoutingPage()
    } else if (this.activeScreen === AppScreen.SETTINGS) {
      this.SettingsPage()
    } else if (this.activeScreen === AppScreen.PER_APP) {
      this.PerAppPage()
    } else if (this.activeScreen === AppScreen.ASSETS) {
      this.AssetsPage()
    } else if (this.activeScreen === AppScreen.LOGS) {
      this.LogsPage()
    } else if (this.activeScreen === AppScreen.SCANNER) {
      this.ScannerPage()
    } else {
      this.AboutPage()
    }
  }

  @Builder
  private ServersPage() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button(this.isRunning() ? this.t('action.stop') : this.t('action.start'))
          .height(42)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.isBusy())
          .backgroundColor(this.isRunning() ? '#B42318' : '#166534')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            if (this.isRunning()) {
              this.stopConnection();
            } else {
              this.startConnection();
            }
          })
        Button(this.t('action.restart'))
          .height(42)
          .width(92)
          .fontSize(13)
          .enabled(!this.isBusy())
          .backgroundColor('#1D4ED8')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(async () => {
            await this.stopConnection();
            await this.startConnection();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ placeholder: this.t('action.search'), text: this.searchQuery })
          .height(38)
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor('#FFFFFF')
          .borderRadius(6)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
        Button(this.t('action.add'))
          .height(38)
          .width(68)
          .fontSize(13)
          .backgroundColor('#E5E7EB')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.activeScreen = AppScreen.IMPORT;
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button(this.t('action.subUpdate'))
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .enabled(!this.subscriptionUpdating && !this.isBusy())
          .backgroundColor('#EEF2FF')
          .fontColor('#3730A3')
          .borderRadius(6)
          .onClick(() => {
            this.updateSubscription();
          })
        Button(this.delayTesting ? this.t('node.delay.testing') : this.t('action.pingAll'))
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .enabled(!this.delayTesting && !this.isBusy())
          .backgroundColor('#F3F4F6')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.testVisibleNodeDelay();
          })
        Button(this.t('action.export'))
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#F3F4F6')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.appendLog(this.f1('log.exportPrepared', 'count', this.nodes.length.toString()));
          })
      }
      .width('100%')

      if (this.lastError.length > 0) {
        Text(this.lastError)
          .fontSize(12)
          .fontColor('#B42318')
          .width('100%')
          .padding(10)
          .backgroundColor('#FEF3F2')
          .borderRadius(6)
      }

      Column({ space: 8 }) {
        ForEach(this.filteredNodes(), (node: ProxyNode) => {
          this.ServerCard(node)
        }, (node: ProxyNode) => node.id)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private ServerCard(node: ProxyNode) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(node.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${node.protocol.toUpperCase()}  ${node.sourceUrl.length > 0 ? this.t('node.source.subscription') : this.t('node.source.manual')}`)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)

      Text(this.nodeDelayText(node))
        .fontSize(12)
        .fontColor(this.nodeDelayColor(node))
        .width(84)
        .textAlign(TextAlign.Center)

      Button(node.id === this.selectedNodeId ? this.t('action.current') : this.t('action.use'))
        .height(34)
        .width(86)
        .fontSize(12)
        .enabled(!this.isBusy())
        .backgroundColor(node.id === this.selectedNodeId ? '#166534' : '#E5E7EB')
        .fontColor(node.id === this.selectedNodeId ? '#FFFFFF' : '#374151')
        .borderRadius(6)
        .onClick(() => {
          this.selectNode(node);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(node.id === this.selectedNodeId ? '#F0FDF4' : '#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private ImportPage() {
    Column({ space: 12 }) {
      Text(this.t('label.protocol'))
        .fontSize(13)
        .fontColor('#6B7280')
        .width('100%')
      Row({ space: 6 }) {
        this.ProtocolButton('vless')
        this.ProtocolButton('vmess')
        this.ProtocolButton('ss')
        this.ProtocolButton('trojan')
      }
      .width('100%')
      Row({ space: 6 }) {
        this.ProtocolButton('socks')
        this.ProtocolButton('http')
        this.ProtocolButton('wireguard')
        this.ProtocolButton('hy2')
      }
      .width('100%')

      TextArea({
        placeholder: this.t('placeholder.importPayload'),
        text: this.importBuffer
      })
        .height(220)
        .fontSize(13)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .padding(10)
        .onChange((value: string) => {
          this.importBuffer = value;
        })

      Row({ space: 8 }) {
        Button(this.t('action.import'))
          .height(40)
          .layoutWeight(1)
          .enabled(!this.isBusy())
          .backgroundColor('#166534')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.importManualConfig();
          })
        Button(this.t('action.useCurrent'))
          .height(40)
          .width(116)
          .backgroundColor('#E5E7EB')
          .fontColor('#374151')
          .borderRadius(8)
          .onClick(() => {
            this.importBuffer = this.outboundJson;
          })
      }
      .width('100%')

      this.ConfigPanel()
    }
    .width('100%')
  }

  @Builder
  private ProtocolButton(protocol: string) {
    Button(protocol.toUpperCase())
      .height(34)
      .layoutWeight(1)
      .fontSize(11)
      .backgroundColor(this.selectedImportProtocol === protocol ? '#111827' : '#E5E7EB')
      .fontColor(this.selectedImportProtocol === protocol ? '#FFFFFF' : '#374151')
      .borderRadius(6)
      .onClick(() => {
        this.selectedImportProtocol = protocol;
      })
  }

  @Builder
  private SubscriptionsPage() {
    Column({ space: 12 }) {
      this.SubscriptionPanel()

      Row({ space: 8 }) {
        Button(this.t('action.updateAll'))
          .height(38)
          .layoutWeight(1)
          .enabled(!this.subscriptionUpdating && !this.isBusy())
          .backgroundColor('#1D4ED8')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.updateSubscription();
          })
        Button(this.t('action.scanUrl'))
          .height(38)
          .width(100)
          .backgroundColor('#E5E7EB')
          .fontColor('#374151')
          .borderRadius(8)
          .onClick(() => {
            this.activeScreen = AppScreen.SCANNER;
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private RoutingPage() {
    Column({ space: 12 }) {
      SectionHeader({ title: this.t('routing.trafficMode'), detail: this.t(`routing.mode.${this.trafficMode}`) })
      Row({ space: 8 }) {
        this.TrafficModeButton('global', this.t('routing.mode.global'))
        this.TrafficModeButton('rules', this.t('routing.mode.rules'))
        this.TrafficModeButton('direct', this.t('routing.mode.direct'))
      }
      .width('100%')

      SectionHeader({ title: this.t('routing.domainStrategy'), detail: this.routingStrategy })
      Row({ space: 8 }) {
        this.StrategyButton('AsIs')
        this.StrategyButton('IPIfNonMatch')
        this.StrategyButton('IPOnDemand')
      }
      .width('100%')

      this.RoutingPreset(this.t('routing.global.title'), this.t('routing.global.detail'))
      this.RoutingPreset(this.t('routing.bypassLanCn.title'), this.t('routing.bypassLanCn.detail'))
      this.RoutingPreset(this.t('routing.blockAds.title'), this.t('routing.blockAds.detail'))
      this.RoutingPreset(this.t('routing.customRulesets.title'), this.t('routing.customRulesets.detail'))
    }
    .width('100%')
  }

  @Builder
  private SettingsPage() {
    Column({ space: 10 }) {
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
      Button(this.t('action.saveSettings'))
        .height(40)
        .width('100%')
        .backgroundColor('#1D4ED8')
        .fontColor('#FFFFFF')
        .borderRadius(8)
        .onClick(() => {
          this.persistSettings();
        })
    }
    .width('100%')
  }

  @Builder
  private PerAppPage() {
    Column({ space: 12 }) {
      this.SettingToggle(this.t('settings.perAppProxy'), 'pref_per_app_proxy', this.settingPerAppProxy, 'perApp')
      this.RoutingPreset(this.t('perApp.proxySelected.title'), this.t('perApp.proxySelected.detail'))
      this.RoutingPreset(this.t('perApp.bypassSelected.title'), this.t('perApp.bypassSelected.detail'))
      this.RoutingPreset(this.t('perApp.systemVisibility.title'), this.t('perApp.systemVisibility.detail'))
    }
    .width('100%')
  }

  @Builder
  private AssetsPage() {
    Column({ space: 12 }) {
      SectionHeader({ title: this.t('assets.section'), detail: this.t('assets.section.detail') })
      this.RoutingPreset('geosite.dat', this.t('assets.geosite.detail'))
      this.RoutingPreset('geoip.dat', this.t('assets.geoip.detail'))
      this.RoutingPreset(this.t('assets.userUrls.title'), this.t('assets.userUrls.detail'))
      this.RoutingPreset(this.t('assets.backupRestore.title'), this.t('assets.backupRestore.detail'))
    }
    .width('100%')
  }

  @Builder
  private LogsPage() {
    Column({ space: 12 }) {
      RuntimeStatusPanel({
        title: this.t('runtime.title'),
        durationLabel: this.t('runtime.duration'),
        durationValue: this.elapsedText,
        uploadLabel: this.t('runtime.upload'),
        uploadValue: formatBytes(this.stats.uploadBytes),
        downloadLabel: this.t('runtime.download'),
        downloadValue: formatBytes(this.stats.downloadBytes),
        xrayActive: this.stats.xrayRunning,
        tunActive: this.stats.tun2SocksRunning,
        lastMessage: this.localizeCoreMessage(this.stats.lastMessage)
      })
      this.LogPanel()
    }
    .width('100%')
  }

  @Builder
  private ScannerPage() {
    Column({ space: 12 }) {
      TextArea({
        placeholder: this.t('placeholder.scannerPayload'),
        text: this.importBuffer
      })
        .height(180)
        .fontSize(13)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .padding(10)
        .onChange((value: string) => {
          this.importBuffer = value;
        })
      Button(this.t('action.importResult'))
        .height(40)
        .width('100%')
        .backgroundColor('#166534')
        .fontColor('#FFFFFF')
        .borderRadius(8)
        .onClick(() => {
          this.importManualConfig();
        })
    }
    .width('100%')
  }

  @Builder
  private AboutPage() {
    Column({ space: 10 }) {
      SectionHeader({ title: 'Hey VPN', detail: this.t('about.section.detail') })
      this.RoutingPreset(this.t('about.source.title'), this.t('about.source.detail'))
      this.RoutingPreset(this.t('about.core.title'), this.t('about.core.detail'))
      this.RoutingPreset(this.t('about.license.title'), this.t('about.license.detail'))
    }
    .width('100%')
  }

  @Builder
  private TrafficModeButton(value: string, label: string) {
    Button(label)
      .height(34)
      .layoutWeight(1)
      .fontSize(12)
      .backgroundColor(this.trafficMode === value ? '#111827' : '#E5E7EB')
      .fontColor(this.trafficMode === value ? '#FFFFFF' : '#374151')
      .borderRadius(6)
      .onClick(() => {
        this.trafficMode = value;
        this.appendLog(this.f1('log.routingStrategy', 'value', label));
        this.persistSettings();
      })
  }

  @Builder
  private StrategyButton(value: string) {
    Button(value)
      .height(34)
      .layoutWeight(1)
      .fontSize(11)
      .backgroundColor(this.routingStrategy === value ? '#111827' : '#E5E7EB')
      .fontColor(this.routingStrategy === value ? '#FFFFFF' : '#374151')
      .borderRadius(6)
      .onClick(() => {
        this.routingStrategy = value;
        this.appendLog(this.f1('log.routingStrategy', 'value', value));
        this.persistSettings();
      })
  }

  @Builder
  private RoutingPreset(title: string, detail: string) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
        Text(detail)
          .fontSize(12)
          .fontColor('#6B7280')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      Button(this.t('action.open'))
        .height(32)
        .width(68)
        .fontSize(12)
        .backgroundColor('#E5E7EB')
        .fontColor('#374151')
        .borderRadius(6)
        .onClick(() => {
          this.appendLog(this.f1('log.presetOpened', 'title', title));
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private SettingToggle(title: string, key: string, enabled: boolean, action: string) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
        Text(key)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)
      Button(enabled ? this.t('action.on') : this.t('action.off'))
        .height(32)
        .width(62)
        .fontSize(12)
        .backgroundColor(enabled ? '#166534' : '#E5E7EB')
        .fontColor(enabled ? '#FFFFFF' : '#374151')
        .borderRadius(6)
        .onClick(() => {
          this.toggleSetting(action);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private LanguageToggle() {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(this.t('settings.language.title'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
        Text(this.t('settings.language.key'))
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)

      Button(this.t('settings.language.zh'))
        .height(32)
        .width(96)
        .fontSize(12)
        .backgroundColor(this.language === 'zh' ? '#111827' : '#E5E7EB')
        .fontColor(this.language === 'zh' ? '#FFFFFF' : '#374151')
        .borderRadius(6)
        .onClick(() => {
          this.changeLanguage('zh');
        })
      Button(this.t('settings.language.en'))
        .height(32)
        .width(96)
        .fontSize(12)
        .backgroundColor(this.language === 'en' ? '#111827' : '#E5E7EB')
        .fontColor(this.language === 'en' ? '#FFFFFF' : '#374151')
        .borderRadius(6)
        .onClick(() => {
          this.changeLanguage('en');
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private SettingInput(title: string, key: string, value: string, action: string) {
    Column({ space: 8 }) {
      Row() {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .layoutWeight(1)
        Text(key)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .width('100%')
      TextInput({ text: value, placeholder: title })
        .height(36)
        .width('100%')
        .fontSize(13)
        .backgroundColor('#F9FAFB')
        .borderRadius(6)
        .onChange((next: string) => {
          this.updateSettingInput(action, next);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private StatusPanel() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 4 }) {
          Text('Hey VPN')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Text('HarmonyOS NEXT / Xray MVP')
            .fontSize(13)
            .fontColor('#6B7280')
        }
        .layoutWeight(1)

        Text(this.statusLabel())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.statusColor())
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.statusBackground())
          .borderRadius(6)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        Button(this.isRunning() ? this.t('action.stop') : this.t('action.start'))
          .height(44)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.isBusy())
          .backgroundColor(this.isRunning() ? '#B42318' : '#166534')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            if (this.isRunning()) {
              this.stopConnection();
            } else {
              this.startConnection();
            }
          })

        Button(this.t('action.save'))
          .height(44)
          .width(96)
          .fontSize(15)
          .enabled(!this.isBusy())
          .backgroundColor('#1D4ED8')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.saveProfileOnly();
          })
      }
      .width('100%')

      if (this.lastError.length > 0) {
        Text(this.lastError)
          .fontSize(13)
          .fontColor('#B42318')
          .width('100%')
          .padding(10)
          .backgroundColor('#FEF3F2')
          .borderRadius(6)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private SubscriptionPanel() {
    Column({ space: 12 }) {
      Row() {
        Text(this.t('subscription.panelTitle'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
        Text(this.f2('subscription.summary', 'groups', this.subscriptionGroups.length.toString(), 'nodes', this.nodes.length.toString()))
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .width('100%')

      TextArea({
        placeholder: this.t('placeholder.subscriptionUrl'),
        text: this.subscriptionUrl
      })
        .height(56)
        .fontSize(13)
        .fontColor('#111827')
        .placeholderColor('#9CA3AF')
        .backgroundColor('#F9FAFB')
        .borderRadius(6)
        .border({ width: 1, color: '#E5E7EB' })
        .padding(10)
        .onChange((value: string) => {
          this.subscriptionUrl = value;
        })

      Row({ space: 8 }) {
        Button(this.t('action.saveGroup'))
          .height(38)
          .width(116)
          .fontSize(14)
          .enabled(!this.subscriptionUpdating && !this.isBusy())
          .backgroundColor('#E5E7EB')
          .fontColor('#374151')
          .borderRadius(8)
          .onClick(() => {
            this.saveSubscriptionGroup();
          })
        Button(this.subscriptionUpdating ? this.t('action.updating') : this.t('action.update'))
          .height(38)
          .width(96)
          .fontSize(14)
          .enabled(!this.subscriptionUpdating && !this.isBusy())
          .backgroundColor('#1D4ED8')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.updateSubscription();
          })
        Text(this.subscriptionMessage)
          .fontSize(13)
          .fontColor('#374151')
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.subscriptionGroups.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.subscriptionGroups, (group: SubscriptionGroup) => {
            this.SubscriptionGroupRow(group)
          }, (group: SubscriptionGroup) => group.id)
        }
        .width('100%')
      }

      if (this.nodes.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.nodes, (node: ProxyNode) => {
            this.NodeRow(node)
          }, (node: ProxyNode) => node.id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private SubscriptionGroupRow(group: SubscriptionGroup) {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text(group.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.f2('group.enabledSummary', 'status', group.enabled ? this.t('common.enabled') : this.t('common.disabled'), 'count', group.nodes.length.toString()))
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)

      Button(group.id === this.selectedGroupId ? this.t('action.current') : this.t('action.open'))
        .height(32)
        .width(76)
        .fontSize(12)
        .backgroundColor(group.id === this.selectedGroupId ? '#166534' : '#E5E7EB')
        .fontColor(group.id === this.selectedGroupId ? '#FFFFFF' : '#374151')
        .borderRadius(6)
        .onClick(() => {
          this.selectSubscriptionGroup(group);
        })
      Button(group.enabled ? this.t('action.on') : this.t('action.off'))
        .height(32)
        .width(58)
        .fontSize(12)
        .backgroundColor(group.enabled ? '#EEF2FF' : '#F3F4F6')
        .fontColor(group.enabled ? '#3730A3' : '#6B7280')
        .borderRadius(6)
        .onClick(() => {
          this.toggleSubscriptionGroup(group);
        })
      Button(this.t('action.del'))
        .height(32)
        .width(54)
        .fontSize(12)
        .backgroundColor('#FEF3F2')
        .fontColor('#B42318')
        .borderRadius(6)
        .onClick(() => {
          this.removeSubscriptionGroup(group);
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(group.id === this.selectedGroupId ? '#F0FDF4' : '#F9FAFB')
    .borderRadius(6)
  }

  @Builder
  private NodeRow(node: ProxyNode) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(node.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(node.protocol.toUpperCase())
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)

      Text(this.nodeDelayText(node))
        .fontSize(12)
        .fontColor(this.nodeDelayColor(node))
        .width(84)
        .textAlign(TextAlign.Center)

      Button(node.id === this.selectedNodeId ? this.t('action.selected') : this.t('action.use'))
        .height(34)
        .width(86)
        .fontSize(13)
        .enabled(!this.isBusy())
        .backgroundColor(node.id === this.selectedNodeId ? '#166534' : '#E5E7EB')
        .fontColor(node.id === this.selectedNodeId ? '#FFFFFF' : '#374151')
        .borderRadius(6)
        .onClick(() => {
          this.selectNode(node);
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(node.id === this.selectedNodeId ? '#F0FDF4' : '#F9FAFB')
    .borderRadius(6)
  }

  @Builder
  private ConfigPanel() {
    Column({ space: 12 }) {
      Row() {
        Text(this.t('config.title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
        Text(this.profileUpdatedAt)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .width('100%')

      TextArea({
        placeholder: this.t('placeholder.outbound'),
        text: this.outboundJson
      })
        .height(220)
        .fontSize(13)
        .fontColor('#111827')
        .placeholderColor('#9CA3AF')
        .backgroundColor('#F9FAFB')
        .borderRadius(6)
        .border({ width: 1, color: '#E5E7EB' })
        .padding(10)
        .onChange((value: string) => {
          this.outboundJson = value;
          this.validateConfig();
        })

      Row({ space: 8 }) {
        Text(this.validationOk ? this.t('config.valid') : this.t('config.invalid'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.validationOk ? '#166534' : '#B42318')
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.validationOk ? '#DCFCE7' : '#FEF3F2')
          .borderRadius(6)
        Text(this.validationMessage)
          .fontSize(13)
          .fontColor('#374151')
          .layoutWeight(1)
        Button(this.t('action.import'))
          .height(32)
          .width(76)
          .fontSize(13)
          .enabled(!this.isBusy())
          .backgroundColor('#E5E7EB')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.normalizeConfigInput();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private LogPanel() {
    Column({ space: 10 }) {
      Row() {
        Text(this.t('logs.title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
        Button(this.t('action.clear'))
          .height(32)
          .width(72)
          .fontSize(13)
          .backgroundColor('#E5E7EB')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.clearLogs();
          })
      }
      .width('100%')

      Column({ space: 6 }) {
        ForEach(this.allLogs(), (item: string, index: number) => {
          Text(item)
            .fontSize(12)
            .fontColor(index === 0 ? '#111827' : '#4B5563')
            .width('100%')
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#F9FAFB')
      .borderRadius(6)
      .constraintSize({ minHeight: 120 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  private async loadInitialState(): Promise<void> {
    await this.loadSettings();
    await this.loadProfile();
    await this.loadSubscription();
  }

  private async loadSettings(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.applySettings(await SettingsStore.load(context));
    } catch (error) {
      this.appendLog(this.f1('error.loadSettings', 'error', JSON.stringify(error)));
    }
  }

  private applySettings(settings: AppSettings): void {
    this.language = normalizeLanguage(settings.language);
    this.settingSniffing = settings.sniffingEnabled;
    this.settingRouteOnly = settings.routeOnlyEnabled;
    this.settingPerAppProxy = settings.perAppProxyEnabled;
    this.settingLocalDns = settings.localDnsEnabled;
    this.settingFakeDns = settings.fakeDnsEnabled;
    this.settingMux = settings.muxEnabled;
    this.settingFragment = settings.fragmentEnabled;
    this.settingProxySharing = settings.proxySharingEnabled;
    this.settingAllowInsecure = settings.allowInsecure;
    this.settingSocksPort = settings.socksPort.toString();
    this.settingRemoteDns = settings.remoteDns;
    this.settingDomesticDns = settings.domesticDns;
    this.settingVpnDns = settings.vpnDns;
    this.settingLogLevel = settings.logLevel;
    this.settingDelayTestUrl = settings.delayTestUrl;
    this.trafficMode = settings.trafficMode;
    this.routingStrategy = settings.routingDomainStrategy;
    this.refreshLocalizedStateText();
  }

  private async loadProfile(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const profile = await ProfileStore.load(context);
      this.outboundJson = profile.outboundJson;
      this.profileUpdatedAtValue = profile.updatedAt;
      this.profileUpdatedAt = this.profileSavedText(profile.updatedAt);
      this.validateConfig();
      this.appendLog(this.t('log.profileLoaded'));
    } catch (error) {
      this.lastError = this.f1('error.loadProfile', 'error', JSON.stringify(error));
      this.appendLog(this.lastError);
    }
  }

  private async loadSubscription(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.load(context);
      this.applySubscription(subscription);

      const selected = this.findNode(subscription.selectedNodeId);
      if (selected !== null) {
        this.outboundJson = selected.outboundJson;
        this.validateConfig();
      }
    } catch (error) {
      this.subscriptionMessage = this.f1('error.loadSubscription', 'error', JSON.stringify(error));
      this.appendLog(this.subscriptionMessage);
    }
  }

  private applySubscription(subscription: SubscriptionProfile): void {
    this.subscriptionUrl = subscription.url;
    this.nodes = subscription.nodes;
    this.selectedNodeId = subscription.selectedNodeId;
    this.subscriptionGroups = subscription.groups;
    this.selectedGroupId = subscription.selectedGroupId;
    this.subscriptionUpdatedAt = subscription.updatedAt;
    this.subscriptionMessage = this.subscriptionStatusText(subscription.updatedAt);
  }

  private async saveProfileOnly(): Promise<void> {
    const saved = await this.saveProfile();
    if (saved !== null) {
      this.appendLog(this.t('log.profileSaved'));
    }
  }

  private async startConnection(): Promise<void> {
    const profile = await this.saveProfile();
    if (profile === null) {
      return;
    }

    this.appendLog(this.t('log.startingVpn'));
    const snapshot = await this.controller.start(profile, this.buildSettingsFromState());
    this.applySnapshot(snapshot);
    this.appendLog(this.status === ConnectionStatus.RUNNING ? this.t('log.vpnStarted') : this.t('log.vpnStartIncomplete'));
  }

  private async stopConnection(): Promise<void> {
    this.appendLog(this.t('log.stoppingVpn'));
    const snapshot = await this.controller.stop();
    this.applySnapshot(snapshot);
    this.appendLog(this.status === ConnectionStatus.IDLE ? this.t('log.vpnStopped') : this.t('log.vpnStopIncomplete'));
  }

  private async saveProfile(): Promise<ProxyProfile | null> {
    const validation = normalizeOutboundInput(this.outboundJson);
    this.validationOk = validation.valid;
    this.validationMessage = this.localizeCoreMessage(validation.message);
    if (!validation.valid) {
      this.lastError = this.validationMessage;
      this.appendLog(this.validationMessage);
      return null;
    }

    try {
      const context = getContext(this) as common.Context;
      const profile = await ProfileStore.save(context, validation.normalizedJson);
      this.outboundJson = validation.normalizedJson;
      this.profileUpdatedAtValue = profile.updatedAt;
      this.profileUpdatedAt = this.profileSavedText(profile.updatedAt);
      this.lastError = '';
      return profile;
    } catch (error) {
      this.lastError = this.f1('error.saveProfile', 'error', JSON.stringify(error));
      this.appendLog(this.lastError);
      return null;
    }
  }

  private async updateSubscription(): Promise<void> {
    if (this.subscriptionUpdating) {
      return;
    }
    const url = this.subscriptionUrl.trim();
    if (url.length === 0) {
      this.subscriptionMessage = this.t('error.emptySubscriptionUrl');
      this.appendLog(this.subscriptionMessage);
      return;
    }

    this.subscriptionUpdating = true;
    this.subscriptionMessage = this.t('log.updatingSubscription');
    this.appendLog(this.t('log.updatingSubscription'));
    try {
      const context = getContext(this) as common.Context;
      await SubscriptionStore.saveUrl(context, url);
      const result: SubscriptionUpdateResult = await SubscriptionManager.fetchAndParse(url);
      if (!result.ok) {
        this.subscriptionMessage = this.localizeCoreMessage(result.message);
        this.appendLog(this.subscriptionMessage);
        this.applySubscription(await SubscriptionStore.load(context));
        return;
      }

      let selectedId = this.selectedNodeId;
      if (this.findNodeInList(result.nodes, selectedId) === null) {
        selectedId = result.nodes[0].id;
      }
      const subscription = await SubscriptionStore.saveNodes(context, url, result.nodes, selectedId);
      this.applySubscription(subscription);
      this.subscriptionMessage = this.localizeCoreMessage(result.message);
      this.appendLog(this.subscriptionMessage);

      const selected = this.findNode(selectedId);
      if (selected !== null) {
        await this.selectNode(selected);
      }
    } catch (error) {
      this.subscriptionMessage = this.f1('error.updateSubscription', 'error', JSON.stringify(error));
      this.appendLog(this.subscriptionMessage);
    } finally {
      this.subscriptionUpdating = false;
    }
  }

  private async saveSubscriptionGroup(): Promise<void> {
    const url = this.subscriptionUrl.trim();
    if (url.length === 0) {
      this.subscriptionMessage = this.t('error.emptySubscriptionUrl');
      this.appendLog(this.subscriptionMessage);
      return;
    }
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.saveUrl(context, url);
      this.applySubscription(subscription);
      this.subscriptionMessage = this.t('log.subscriptionGroupSaved');
      this.appendLog(this.subscriptionMessage);
    } catch (error) {
      this.subscriptionMessage = this.f1('error.saveSubscriptionGroup', 'error', JSON.stringify(error));
      this.appendLog(this.subscriptionMessage);
    }
  }

  private async selectSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.selectGroup(context, group.id);
      this.applySubscription(subscription);
      const selected = this.findNode(subscription.selectedNodeId);
      if (selected !== null) {
        await this.selectNode(selected);
      }
      this.appendLog(this.f1('log.openedSubscriptionGroup', 'name', group.name));
    } catch (error) {
      this.subscriptionMessage = this.f1('error.selectSubscriptionGroup', 'error', JSON.stringify(error));
      this.appendLog(this.subscriptionMessage);
    }
  }

  private async toggleSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.toggleGroup(context, group.id);
      this.applySubscription(subscription);
      this.appendLog(this.f2('log.subscriptionGroupToggled', 'name', group.name, 'status', group.enabled ? this.t('common.disabled') : this.t('common.enabled')));
    } catch (error) {
      this.subscriptionMessage = this.f1('error.toggleSubscriptionGroup', 'error', JSON.stringify(error));
      this.appendLog(this.subscriptionMessage);
    }
  }

  private async removeSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.removeGroup(context, group.id);
      this.applySubscription(subscription);
      this.appendLog(this.f1('log.removedSubscriptionGroup', 'name', group.name));
    } catch (error) {
      this.subscriptionMessage = this.f1('error.removeSubscriptionGroup', 'error', JSON.stringify(error));
      this.appendLog(this.subscriptionMessage);
    }
  }

  private async selectNode(node: ProxyNode): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.selectNode(context, node.id);
      const profile = await ProfileStore.save(context, node.outboundJson);
      this.applySubscription(subscription);
      this.selectedNodeId = node.id;
      this.outboundJson = node.outboundJson;
      this.profileUpdatedAtValue = profile.updatedAt;
      this.profileUpdatedAt = this.profileSavedText(profile.updatedAt);
      this.validateConfig();
      this.lastError = '';
      this.appendLog(this.f1('log.selectedNode', 'name', node.name));
    } catch (error) {
      this.lastError = this.f1('error.selectNode', 'error', JSON.stringify(error));
      this.appendLog(this.lastError);
    }
  }

  private findNode(nodeId: string): ProxyNode | null {
    return this.findNodeInList(this.nodes, nodeId);
  }

  private findNodeInList(nodes: Array<ProxyNode>, nodeId: string): ProxyNode | null {
    for (let index = 0; index < nodes.length; index++) {
      if (nodes[index].id === nodeId) {
        return nodes[index];
      }
    }
    return null;
  }

  private validateConfig(): void {
    const validation = normalizeOutboundInput(this.outboundJson);
    this.validationOk = validation.valid;
    this.validationMessage = this.localizeCoreMessage(validation.message);
  }

  private normalizeConfigInput(): void {
    const validation = normalizeOutboundInput(this.outboundJson);
    this.validationOk = validation.valid;
    this.validationMessage = this.localizeCoreMessage(validation.message);
    if (!validation.valid) {
      this.lastError = this.validationMessage;
      this.appendLog(this.validationMessage);
      return;
    }

    this.outboundJson = validation.normalizedJson;
    this.lastError = '';
    this.appendLog(this.t('log.configImported'));
  }

  private applySnapshot(snapshot: ConnectionSnapshot): void {
    this.status = snapshot.status;
    this.startedAt = snapshot.startedAt;
    this.lastError = this.localizeCoreMessage(snapshot.lastError);
    this.refreshRuntime();
  }

  private refreshRuntime(): void {
    this.stats = this.controller.getStats();
    this.refreshDiagnostics();
    if (this.startedAt <= 0 || this.status !== ConnectionStatus.RUNNING) {
      this.elapsedText = '00:00';
      return;
    }
    const seconds = Math.max(0, Math.floor((Date.now() - this.startedAt) / 1000));
    this.elapsedText = formatDuration(seconds);
  }

  private appendLog(message: string): void {
    const line = `${formatClockTime(Date.now())}  ${message}`;
    const next = [line].concat(this.logs);
    this.logs = next.slice(0, 80);
  }

  private clearLogs(): void {
    try {
      const context = getContext(this) as common.Context;
      DiagnosticLog.clear(context);
    } catch (error) {
      this.appendLog(this.f1('error.clearDiagnostics', 'error', JSON.stringify(error)));
    }
    this.logs = [];
    this.diagnosticLogs = [];
  }

  private allLogs(): Array<string> {
    return this.diagnosticLogs.concat(this.logs).slice(0, 120);
  }

  private async refreshDiagnostics(): Promise<void> {
    if (this.diagnosticRefreshing) {
      return;
    }
    this.diagnosticRefreshing = true;

    try {
      const context = getContext(this) as common.Context;
      const events = await DiagnosticLog.read(context, 80);
      this.diagnosticLogs = events.map((event: DiagnosticEvent) => DiagnosticLog.format(event, (value: number) => formatClockTime(value)));
      this.applyDiagnosticStats(events);
      this.applyDiagnosticError(events);
    } finally {
      this.diagnosticRefreshing = false;
    }
  }

  private applyDiagnosticStats(events: Array<DiagnosticEvent>): void {
    for (let index = 0; index < events.length; index++) {
      const event = events[index];
      if (event.uploadBytes !== undefined || event.downloadBytes !== undefined) {
        this.stats = {
          uploadBytes: event.uploadBytes ?? 0,
          downloadBytes: event.downloadBytes ?? 0,
          xrayRunning: event.xrayRunning ?? false,
          tun2SocksRunning: event.tun2SocksRunning ?? false,
          lastMessage: event.details ?? event.message
        };
        return;
      }
    }
  }

  private applyDiagnosticError(events: Array<DiagnosticEvent>): void {
    if (events.length === 0) {
      return;
    }
    const event = events[0];
    if (event.level !== 'error') {
      return;
    }
    const message = event.details !== undefined && event.details.length > 0 ? `${event.message} ${event.details}` : event.message;
    this.lastError = this.localizeCoreMessage(message);
    if (this.status === ConnectionStatus.RUNNING || this.status === ConnectionStatus.STARTING) {
      this.status = ConnectionStatus.ERROR;
    }
  }

  private activeScreenTitle(): string {
    for (let index = 0; index < SCREEN_ENTRIES.length; index++) {
      if (SCREEN_ENTRIES[index].id === this.activeScreen) {
        return this.t(SCREEN_ENTRIES[index].titleKey);
      }
    }
    return 'Hey VPN';
  }

  private filteredNodes(): Array<ProxyNode> {
    const keyword = this.searchQuery.trim().toLowerCase();
    if (keyword.length === 0) {
      return this.nodes;
    }
    const result: Array<ProxyNode> = [];
    for (let index = 0; index < this.nodes.length; index++) {
      const node = this.nodes[index];
      const value = `${node.name} ${node.protocol} ${node.sourceUrl}`.toLowerCase();
      if (value.indexOf(keyword) >= 0) {
        result.push(node);
      }
    }
    return result;
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

  private async importManualConfig(): Promise<void> {
    const value = this.importBuffer.trim();
    if (value.length === 0) {
      this.lastError = this.t('error.emptyImport');
      this.appendLog(this.lastError);
      return;
    }

    if (value.toLowerCase().startsWith('http://') || value.toLowerCase().startsWith('https://')) {
      this.subscriptionUrl = value;
      this.activeScreen = AppScreen.SUBSCRIPTIONS;
      await this.updateSubscription();
      return;
    }

    this.outboundJson = value;
    this.normalizeConfigInput();
    if (!this.validationOk) {
      return;
    }
    await this.saveProfileOnly();
    this.importBuffer = this.outboundJson;
    this.activeScreen = AppScreen.SERVERS;
  }

  private async testVisibleNodeDelay(): Promise<void> {
    if (this.delayTesting) {
      return;
    }
    const targets = this.filteredNodes();
    if (targets.length === 0) {
      return;
    }

    this.delayTesting = true;
    this.appendLog(this.t('log.delayQueued'));
    try {
      const context = getContext(this) as common.Context;
      for (let index = 0; index < targets.length; index++) {
        const node = targets[index];
        const startedAt = Date.now();
        this.markNodeDelay(node.id, -1, 'testing', startedAt);
        this.appendLog(this.f1('log.delayTestingNode', 'name', node.name));
        const result: DelayTestResult = await DelayTester.measure(this.settingDelayTestUrl, 8000);
        const delayMs = result.ok ? result.delayMs : -1;
        const status = result.ok ? 'ok' : result.status;
        const subscription = await SubscriptionStore.saveNodeDelay(context, node.id, delayMs, status, Date.now());
        this.applySubscription(subscription);
        this.appendLog(this.f2('log.delayResult', 'name', node.name, 'result', this.delayResultText(result)));
      }
    } catch (error) {
      this.lastError = this.f1('error.delayTest', 'error', JSON.stringify(error));
      this.appendLog(this.lastError);
    } finally {
      this.delayTesting = false;
    }
  }

  private markNodeDelay(nodeId: string, delayMs: number, delayStatus: string, delayTestAt: number): void {
    const next = new Array<ProxyNode>();
    for (let index = 0; index < this.nodes.length; index++) {
      const node = this.nodes[index];
      if (node.id === nodeId) {
        const updated: ProxyNode = {
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
        };
        next.push(updated);
      } else {
        next.push(node);
      }
    }
    this.nodes = next;
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
    this.appendLog(this.f1('log.settingsChanged', 'action', action));
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

  private async persistSettings(showMessage: boolean = true): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const saved = await SettingsStore.save(context, this.buildSettingsFromState());
      this.applySettings(saved);
      if (showMessage) {
        this.appendLog(this.t('log.settingsSaved'));
      }
    } catch (error) {
      this.lastError = this.f1('error.saveSettings', 'error', JSON.stringify(error));
      this.appendLog(this.lastError);
    }
  }

  private async changeLanguage(language: AppLanguage): Promise<void> {
    if (this.language === language) {
      return;
    }
    this.language = language;
    try {
      const context = getContext(this) as common.Context;
      const saved = await SettingsStore.save(context, this.buildSettingsFromState());
      this.applySettings(saved);
      const label = this.language === 'zh' ? this.t('settings.language.zh') : this.t('settings.language.en');
      this.appendLog(this.f1('log.languageChanged', 'language', label));
    } catch (error) {
      this.lastError = this.f1('error.saveSettings', 'error', JSON.stringify(error));
      this.appendLog(this.lastError);
    }
  }

  private buildSettingsFromState(): AppSettings {
    return {
      language: this.language,
      sniffingEnabled: this.settingSniffing,
      routeOnlyEnabled: this.settingRouteOnly,
      perAppProxyEnabled: this.settingPerAppProxy,
      localDnsEnabled: this.settingLocalDns,
      fakeDnsEnabled: this.settingFakeDns,
      appendHttpProxy: DEFAULT_APP_SETTINGS.appendHttpProxy,
      muxEnabled: this.settingMux,
      muxConcurrency: DEFAULT_APP_SETTINGS.muxConcurrency,
      muxXudpConcurrency: DEFAULT_APP_SETTINGS.muxXudpConcurrency,
      muxXudpQuic: DEFAULT_APP_SETTINGS.muxXudpQuic,
      fragmentEnabled: this.settingFragment,
      fragmentPackets: DEFAULT_APP_SETTINGS.fragmentPackets,
      fragmentLength: DEFAULT_APP_SETTINGS.fragmentLength,
      fragmentInterval: DEFAULT_APP_SETTINGS.fragmentInterval,
      preferIpv6: DEFAULT_APP_SETTINGS.preferIpv6,
      proxySharingEnabled: this.settingProxySharing,
      allowInsecure: this.settingAllowInsecure,
      socksPort: this.parsePortSetting(this.settingSocksPort, DEFAULT_APP_SETTINGS.socksPort),
      localDnsPort: DEFAULT_APP_SETTINGS.localDnsPort,
      vpnDns: this.settingVpnDns.trim(),
      remoteDns: this.settingRemoteDns.trim(),
      domesticDns: this.settingDomesticDns.trim(),
      dnsHosts: DEFAULT_APP_SETTINGS.dnsHosts,
      delayTestUrl: this.settingDelayTestUrl.trim(),
      logLevel: this.settingLogLevel.trim().length > 0 ? this.settingLogLevel.trim() : DEFAULT_APP_SETTINGS.logLevel,
      mode: DEFAULT_APP_SETTINGS.mode,
      trafficMode: this.trafficMode,
      routingDomainStrategy: this.routingStrategy
    };
  }

  private parsePortSetting(value: string, fallback: number): number {
    const parsed = Number(value);
    if (Number.isNaN(parsed) || parsed < 1 || parsed > 65535 || Math.floor(parsed) !== parsed) {
      return fallback;
    }
    return parsed;
  }

  private refreshLocalizedStateText(): void {
    this.profileUpdatedAt = this.profileSavedText(this.profileUpdatedAtValue);
    if (!this.subscriptionUpdating) {
      this.subscriptionMessage = this.subscriptionStatusText(this.subscriptionUpdatedAt);
    }
    this.validateConfig();
  }

  private profileSavedText(updatedAt: number): string {
    return localizedProfileSavedText(this.language, updatedAt);
  }

  private subscriptionStatusText(updatedAt: number): string {
    return localizedSubscriptionStatusText(this.language, updatedAt);
  }

  private localizeCoreMessage(message: string): string {
    return localizeCoreMessage(this.language, message);
  }

  private statusLabel(): string {
    return localizedConnectionStatus(this.language, this.status);
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

  private statusColor(): string {
    return connectionStatusColor(this.status);
  }

  private statusBackground(): string {
    return connectionStatusBackground(this.status);
  }

  private isRunning(): boolean {
    return this.status === ConnectionStatus.RUNNING;
  }

  private isBusy(): boolean {
    return this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.STOPPING;
  }

}
