import { common } from '@kit.AbilityKit';
import { ConnectionStatus, ProxyNode, ProxyProfile, RuntimeStats, SubscriptionGroup, SubscriptionProfile } from '../core/Profile';
import { normalizeOutboundInput } from '../core/XrayConfig';
import { ConnectionController, ConnectionSnapshot } from '../services/ConnectionController';
import { DiagnosticEvent, DiagnosticLog } from '../services/DiagnosticLog';
import { SubscriptionManager, SubscriptionUpdateResult } from '../services/SubscriptionManager';
import { ProfileStore } from '../storage/ProfileStore';
import { SubscriptionStore } from '../storage/SubscriptionStore';

const EMPTY_STATS: RuntimeStats = {
  uploadBytes: 0,
  downloadBytes: 0,
  xrayRunning: false,
  tun2SocksRunning: false,
  lastMessage: 'Native bridge not queried yet.'
};

enum AppScreen {
  SERVERS = 'servers',
  IMPORT = 'import',
  SUBSCRIPTIONS = 'subscriptions',
  ROUTING = 'routing',
  SETTINGS = 'settings',
  PER_APP = 'perApp',
  ASSETS = 'assets',
  LOGS = 'logs',
  SCANNER = 'scanner',
  ABOUT = 'about'
}

interface ScreenEntry {
  id: AppScreen;
  label: string;
  title: string;
}

const SCREEN_ENTRIES: Array<ScreenEntry> = [
  { id: AppScreen.SERVERS, label: 'Nodes', title: 'Server List' },
  { id: AppScreen.IMPORT, label: 'Add', title: 'Add Config' },
  { id: AppScreen.SUBSCRIPTIONS, label: 'Subs', title: 'Subscriptions' },
  { id: AppScreen.ROUTING, label: 'Route', title: 'Routing' },
  { id: AppScreen.SETTINGS, label: 'Config', title: 'Settings' },
  { id: AppScreen.PER_APP, label: 'Apps', title: 'Per-App Proxy' },
  { id: AppScreen.ASSETS, label: 'Assets', title: 'User Assets' },
  { id: AppScreen.LOGS, label: 'Logs', title: 'Logcat' },
  { id: AppScreen.SCANNER, label: 'Scan', title: 'Scanner' },
  { id: AppScreen.ABOUT, label: 'About', title: 'About' }
];

@Entry
@Component
struct Index {
  private controller: ConnectionController = new ConnectionController();
  private timerId: number = -1;

  @State private outboundJson: string = '';
  @State private status: ConnectionStatus = ConnectionStatus.IDLE;
  @State private startedAt: number = 0;
  @State private elapsedText: string = '00:00';
  @State private validationMessage: string = '等待粘贴 Xray outbound JSON 或分享链接。';
  @State private validationOk: boolean = false;
  @State private lastError: string = '';
  @State private logs: Array<string> = ['Ready. Paste one Xray outbound JSON or share link to begin.'];
  @State private diagnosticLogs: Array<string> = [];
  @State private stats: RuntimeStats = EMPTY_STATS;
  @State private profileUpdatedAt: string = 'Not saved';
  @State private subscriptionUrl: string = '';
  @State private nodes: Array<ProxyNode> = [];
  @State private selectedNodeId: string = '';
  @State private subscriptionMessage: string = 'No subscription loaded.';
  @State private subscriptionUpdating: boolean = false;
  @State private subscriptionGroups: Array<SubscriptionGroup> = [];
  @State private selectedGroupId: string = '';
  @State private activeScreen: AppScreen = AppScreen.SERVERS;
  @State private searchQuery: string = '';
  @State private importBuffer: string = '';
  @State private selectedImportProtocol: string = 'vless';
  @State private routingStrategy: string = 'AsIs';
  @State private settingSniffing: boolean = true;
  @State private settingRouteOnly: boolean = false;
  @State private settingLocalDns: boolean = false;
  @State private settingFakeDns: boolean = false;
  @State private settingMux: boolean = false;
  @State private settingFragment: boolean = false;
  @State private settingProxySharing: boolean = false;
  @State private settingAllowInsecure: boolean = false;
  @State private settingPerAppProxy: boolean = false;
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
      this.NavigationRail()
      Column() {
        this.TopBar()
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
  private NavigationRail() {
    Column({ space: 8 }) {
      Text('Hey')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })

      ForEach(SCREEN_ENTRIES, (entry: ScreenEntry) => {
        Button(entry.label)
          .height(36)
          .width('100%')
          .fontSize(12)
          .fontColor(this.activeScreen === entry.id ? '#111827' : '#D1D5DB')
          .backgroundColor(this.activeScreen === entry.id ? '#FFFFFF' : '#111827')
          .borderRadius(6)
          .onClick(() => {
            this.activeScreen = entry.id;
          })
      }, (entry: ScreenEntry) => entry.id)
    }
    .height('100%')
    .width(92)
    .padding({ left: 10, right: 10, top: 18, bottom: 18 })
    .backgroundColor('#111827')
  }

  @Builder
  private TopBar() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.activeScreenTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
        Text(`${this.nodes.length} nodes / ${this.statusLabel()}`)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)

      Text(this.statusLabel())
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.statusColor())
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.statusBackground())
        .borderRadius(6)
    }
    .width('100%')
    .height(70)
    .padding({ left: 14, right: 14 })
    .backgroundColor('#FFFFFF')
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
        Button(this.isRunning() ? 'Stop' : 'Start')
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
        Button('Restart')
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
        TextInput({ placeholder: 'Search', text: this.searchQuery })
          .height(38)
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor('#FFFFFF')
          .borderRadius(6)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
        Button('Add')
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
        Button('Sub Update')
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
        Button('Ping All')
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#F3F4F6')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.appendLog('Delay test queued for all visible nodes.');
          })
        Button('Export')
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#F3F4F6')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.appendLog(`Export prepared for ${this.nodes.length} nodes.`);
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
        Text(`${node.protocol.toUpperCase()}  ${node.sourceUrl.length > 0 ? 'subscription' : 'manual'}`)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)

      Button(node.id === this.selectedNodeId ? 'Current' : 'Use')
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
      Text('Protocol')
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
        placeholder: 'Paste share link, subscription item, or outbound JSON.',
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
        Button('Import')
          .height(40)
          .layoutWeight(1)
          .enabled(!this.isBusy())
          .backgroundColor('#166534')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.importManualConfig();
          })
        Button('Use Current')
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
        Button('Update All')
          .height(38)
          .layoutWeight(1)
          .enabled(!this.subscriptionUpdating && !this.isBusy())
          .backgroundColor('#1D4ED8')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            this.updateSubscription();
          })
        Button('Scan URL')
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
      this.SectionHeader('Domain Strategy', this.routingStrategy)
      Row({ space: 8 }) {
        this.StrategyButton('AsIs')
        this.StrategyButton('IPIfNonMatch')
        this.StrategyButton('IPOnDemand')
      }
      .width('100%')

      this.RoutingPreset('Global', 'All traffic uses proxy outbound.')
      this.RoutingPreset('Bypass LAN/CN', 'Private and domestic destinations use direct outbound.')
      this.RoutingPreset('Block Ads', 'Ad domains use block outbound.')
      this.RoutingPreset('Custom Rulesets', 'Manage domain, IP, protocol and app rules.')
    }
    .width('100%')
  }

  @Builder
  private SettingsPage() {
    Column({ space: 10 }) {
      this.SectionHeader('Core', 'Xray runtime preferences')
      this.SettingToggle('Sniffing', 'pref_sniffing_enabled', this.settingSniffing, 'sniffing')
      this.SettingToggle('Route Only', 'pref_route_only_enabled', this.settingRouteOnly, 'routeOnly')
      this.SettingToggle('Allow Insecure', 'pref_allow_insecure', this.settingAllowInsecure, 'allowInsecure')
      this.SectionHeader('VPN', 'TUN and DNS preferences')
      this.SettingToggle('Per-App Proxy', 'pref_per_app_proxy', this.settingPerAppProxy, 'perApp')
      this.SettingToggle('Local DNS', 'pref_local_dns_enabled', this.settingLocalDns, 'localDns')
      this.SettingToggle('Fake DNS', 'pref_fake_dns_enabled', this.settingFakeDns, 'fakeDns')
      this.SettingToggle('Proxy Sharing', 'pref_proxy_sharing_enabled', this.settingProxySharing, 'proxySharing')
      this.SectionHeader('Transport', 'Mux and fragmentation')
      this.SettingToggle('Mux', 'pref_mux_enabled', this.settingMux, 'mux')
      this.SettingToggle('Fragment', 'pref_fragment_enabled', this.settingFragment, 'fragment')
    }
    .width('100%')
  }

  @Builder
  private PerAppPage() {
    Column({ space: 12 }) {
      this.SettingToggle('Enable Per-App Proxy', 'pref_per_app_proxy', this.settingPerAppProxy, 'perApp')
      this.RoutingPreset('Proxy selected apps', 'Application bundle allowlist.')
      this.RoutingPreset('Bypass selected apps', 'Application bundle blocklist.')
      this.RoutingPreset('System app visibility', 'Include or hide system bundles.')
    }
    .width('100%')
  }

  @Builder
  private AssetsPage() {
    Column({ space: 12 }) {
      this.SectionHeader('Assets', 'Geo and custom routing resources')
      this.RoutingPreset('geosite.dat', 'Ruleset asset used by routing.')
      this.RoutingPreset('geoip.dat', 'IP database asset used by routing.')
      this.RoutingPreset('User Asset URLs', 'Remote assets and local refresh list.')
      this.RoutingPreset('Backup / Restore', 'Import and export app profiles.')
    }
    .width('100%')
  }

  @Builder
  private LogsPage() {
    Column({ space: 12 }) {
      this.RuntimePanel()
      this.LogPanel()
    }
    .width('100%')
  }

  @Builder
  private ScannerPage() {
    Column({ space: 12 }) {
      TextArea({
        placeholder: 'Paste scanned QR result or URL scheme payload.',
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
      Button('Import Result')
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
      this.SectionHeader('Hey VPN', 'HarmonyOS NEXT Xray client')
      this.RoutingPreset('Source Reference', 'Function parity target: v2rayNG Android business flows.')
      this.RoutingPreset('Core', 'Xray executable mode plus tun2socks adapter.')
      this.RoutingPreset('License Note', 'Feature parity implementation; Android code and resources are not copied.')
    }
    .width('100%')
  }

  @Builder
  private SectionHeader(title: string, detail: string) {
    Row() {
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .layoutWeight(1)
      Text(detail)
        .fontSize(12)
        .fontColor('#6B7280')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
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
        this.appendLog(`Routing strategy: ${value}`);
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
      Button('Open')
        .height(32)
        .width(68)
        .fontSize(12)
        .backgroundColor('#E5E7EB')
        .fontColor('#374151')
        .borderRadius(6)
        .onClick(() => {
          this.appendLog(`${title} opened.`);
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
      Button(enabled ? 'On' : 'Off')
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
        Button(this.isRunning() ? 'Stop' : 'Start')
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

        Button('Save')
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
        Text('Subscription Groups')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
        Text(`${this.subscriptionGroups.length} groups / ${this.nodes.length} nodes`)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .width('100%')

      TextArea({
        placeholder: 'Paste subscription URL.',
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
        Button('Save Group')
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
        Button(this.subscriptionUpdating ? 'Updating' : 'Update')
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
        Text(`${group.enabled ? 'Enabled' : 'Disabled'} / ${group.nodes.length} nodes`)
          .fontSize(12)
          .fontColor('#6B7280')
      }
      .layoutWeight(1)

      Button(group.id === this.selectedGroupId ? 'Current' : 'Open')
        .height(32)
        .width(76)
        .fontSize(12)
        .backgroundColor(group.id === this.selectedGroupId ? '#166534' : '#E5E7EB')
        .fontColor(group.id === this.selectedGroupId ? '#FFFFFF' : '#374151')
        .borderRadius(6)
        .onClick(() => {
          this.selectSubscriptionGroup(group);
        })
      Button(group.enabled ? 'On' : 'Off')
        .height(32)
        .width(58)
        .fontSize(12)
        .backgroundColor(group.enabled ? '#EEF2FF' : '#F3F4F6')
        .fontColor(group.enabled ? '#3730A3' : '#6B7280')
        .borderRadius(6)
        .onClick(() => {
          this.toggleSubscriptionGroup(group);
        })
      Button('Del')
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

      Button(node.id === this.selectedNodeId ? 'Selected' : 'Use')
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
        Text('Outbound Config')
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
        placeholder: 'Paste outbound JSON, vless:// link, or trojan:// link.',
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
        Text(this.validationOk ? 'Valid' : 'Invalid')
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
        Button('Import')
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
  private RuntimePanel() {
    Column({ space: 12 }) {
      Text('Runtime')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .width('100%')

      Row({ space: 10 }) {
        this.MetricTile('Duration', this.elapsedText)
        this.MetricTile('Upload', this.formatBytes(this.stats.uploadBytes))
        this.MetricTile('Download', this.formatBytes(this.stats.downloadBytes))
      }
      .width('100%')

      Row({ space: 8 }) {
        this.FlagTile('Xray', this.stats.xrayRunning)
        this.FlagTile('TUN', this.stats.tun2SocksRunning)
      }
      .width('100%')

      Text(this.stats.lastMessage)
        .fontSize(12)
        .fontColor('#4B5563')
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private MetricTile(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#6B7280')
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
    }
    .layoutWeight(1)
    .height(64)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F9FAFB')
    .borderRadius(6)
  }

  @Builder
  private FlagTile(label: string, active: boolean) {
    Row({ space: 8 }) {
      Circle()
        .width(8)
        .height(8)
        .fill(active ? '#16A34A' : '#9CA3AF')
      Text(label)
        .fontSize(13)
        .fontColor('#374151')
    }
    .height(34)
    .padding({ left: 10, right: 10 })
    .backgroundColor('#F9FAFB')
    .borderRadius(6)
  }

  @Builder
  private LogPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('Logs')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
        Button('Clear')
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
    await this.loadProfile();
    await this.loadSubscription();
  }

  private async loadProfile(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const profile = await ProfileStore.load(context);
      this.outboundJson = profile.outboundJson;
      this.profileUpdatedAt = profile.updatedAt > 0 ? `Saved ${this.formatTime(profile.updatedAt)}` : 'Not saved';
      this.validateConfig();
      this.appendLog('Profile loaded.');
    } catch (error) {
      this.lastError = `加载配置失败：${JSON.stringify(error)}`;
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
      this.subscriptionMessage = `加载订阅失败：${JSON.stringify(error)}`;
      this.appendLog(this.subscriptionMessage);
    }
  }

  private applySubscription(subscription: SubscriptionProfile): void {
    this.subscriptionUrl = subscription.url;
    this.nodes = subscription.nodes;
    this.selectedNodeId = subscription.selectedNodeId;
    this.subscriptionGroups = subscription.groups;
    this.selectedGroupId = subscription.selectedGroupId;
    this.subscriptionMessage = subscription.updatedAt > 0 ? `Updated ${this.formatTime(subscription.updatedAt)}` : 'No subscription loaded.';
  }

  private async saveProfileOnly(): Promise<void> {
    const saved = await this.saveProfile();
    if (saved !== null) {
      this.appendLog('Profile saved.');
    }
  }

  private async startConnection(): Promise<void> {
    const profile = await this.saveProfile();
    if (profile === null) {
      return;
    }

    this.appendLog('Starting VPN extension.');
    const snapshot = await this.controller.start(profile);
    this.applySnapshot(snapshot);
    this.appendLog(this.status === ConnectionStatus.RUNNING ? 'VPN extension started.' : 'VPN start did not complete.');
  }

  private async stopConnection(): Promise<void> {
    this.appendLog('Stopping VPN extension.');
    const snapshot = await this.controller.stop();
    this.applySnapshot(snapshot);
    this.appendLog(this.status === ConnectionStatus.IDLE ? 'VPN extension stopped.' : 'VPN stop did not complete.');
  }

  private async saveProfile(): Promise<ProxyProfile | null> {
    const validation = normalizeOutboundInput(this.outboundJson);
    this.validationOk = validation.valid;
    this.validationMessage = validation.message;
    if (!validation.valid) {
      this.lastError = validation.message;
      this.appendLog(validation.message);
      return null;
    }

    try {
      const context = getContext(this) as common.Context;
      const profile = await ProfileStore.save(context, validation.normalizedJson);
      this.outboundJson = validation.normalizedJson;
      this.profileUpdatedAt = `Saved ${this.formatTime(profile.updatedAt)}`;
      this.lastError = '';
      return profile;
    } catch (error) {
      this.lastError = `保存配置失败：${JSON.stringify(error)}`;
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
      this.subscriptionMessage = '订阅链接为空。';
      this.appendLog(this.subscriptionMessage);
      return;
    }

    this.subscriptionUpdating = true;
    this.subscriptionMessage = 'Updating subscription.';
    this.appendLog('Updating subscription.');
    try {
      const context = getContext(this) as common.Context;
      await SubscriptionStore.saveUrl(context, url);
      const result: SubscriptionUpdateResult = await SubscriptionManager.fetchAndParse(url);
      if (!result.ok) {
        this.subscriptionMessage = result.message;
        this.appendLog(result.message);
        this.applySubscription(await SubscriptionStore.load(context));
        return;
      }

      let selectedId = this.selectedNodeId;
      if (this.findNodeInList(result.nodes, selectedId) === null) {
        selectedId = result.nodes[0].id;
      }
      const subscription = await SubscriptionStore.saveNodes(context, url, result.nodes, selectedId);
      this.applySubscription(subscription);
      this.subscriptionMessage = result.message;
      this.appendLog(result.message);

      const selected = this.findNode(selectedId);
      if (selected !== null) {
        await this.selectNode(selected);
      }
    } catch (error) {
      this.subscriptionMessage = `订阅更新失败：${JSON.stringify(error)}`;
      this.appendLog(this.subscriptionMessage);
    } finally {
      this.subscriptionUpdating = false;
    }
  }

  private async saveSubscriptionGroup(): Promise<void> {
    const url = this.subscriptionUrl.trim();
    if (url.length === 0) {
      this.subscriptionMessage = '订阅链接为空。';
      this.appendLog(this.subscriptionMessage);
      return;
    }
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.saveUrl(context, url);
      this.applySubscription(subscription);
      this.subscriptionMessage = 'Subscription group saved.';
      this.appendLog(this.subscriptionMessage);
    } catch (error) {
      this.subscriptionMessage = `保存订阅组失败：${JSON.stringify(error)}`;
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
      this.appendLog(`Opened subscription group: ${group.name}`);
    } catch (error) {
      this.subscriptionMessage = `选择订阅组失败：${JSON.stringify(error)}`;
      this.appendLog(this.subscriptionMessage);
    }
  }

  private async toggleSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.toggleGroup(context, group.id);
      this.applySubscription(subscription);
      this.appendLog(`${group.name}: ${group.enabled ? 'disabled' : 'enabled'}`);
    } catch (error) {
      this.subscriptionMessage = `切换订阅组失败：${JSON.stringify(error)}`;
      this.appendLog(this.subscriptionMessage);
    }
  }

  private async removeSubscriptionGroup(group: SubscriptionGroup): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      const subscription = await SubscriptionStore.removeGroup(context, group.id);
      this.applySubscription(subscription);
      this.appendLog(`Removed subscription group: ${group.name}`);
    } catch (error) {
      this.subscriptionMessage = `删除订阅组失败：${JSON.stringify(error)}`;
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
      this.profileUpdatedAt = `Saved ${this.formatTime(profile.updatedAt)}`;
      this.validateConfig();
      this.lastError = '';
      this.appendLog(`Selected node: ${node.name}`);
    } catch (error) {
      this.lastError = `选择节点失败：${JSON.stringify(error)}`;
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
    this.validationMessage = validation.message;
  }

  private normalizeConfigInput(): void {
    const validation = normalizeOutboundInput(this.outboundJson);
    this.validationOk = validation.valid;
    this.validationMessage = validation.message;
    if (!validation.valid) {
      this.lastError = validation.message;
      this.appendLog(validation.message);
      return;
    }

    this.outboundJson = validation.normalizedJson;
    this.lastError = '';
    this.appendLog('Config imported and normalized.');
  }

  private applySnapshot(snapshot: ConnectionSnapshot): void {
    this.status = snapshot.status;
    this.startedAt = snapshot.startedAt;
    this.lastError = snapshot.lastError;
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
    const minutes = Math.floor(seconds / 60);
    const remain = seconds % 60;
    this.elapsedText = `${this.pad2(minutes)}:${this.pad2(remain)}`;
  }

  private appendLog(message: string): void {
    const line = `${this.formatTime(Date.now())}  ${message}`;
    const next = [line].concat(this.logs);
    this.logs = next.slice(0, 80);
  }

  private clearLogs(): void {
    try {
      const context = getContext(this) as common.Context;
      DiagnosticLog.clear(context);
    } catch (error) {
      this.appendLog(`清理诊断日志失败：${JSON.stringify(error)}`);
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
      this.diagnosticLogs = events.map((event: DiagnosticEvent) => DiagnosticLog.format(event, (value: number) => this.formatTime(value)));
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
    this.lastError = message;
    if (this.status === ConnectionStatus.RUNNING || this.status === ConnectionStatus.STARTING) {
      this.status = ConnectionStatus.ERROR;
    }
  }

  private activeScreenTitle(): string {
    for (let index = 0; index < SCREEN_ENTRIES.length; index++) {
      if (SCREEN_ENTRIES[index].id === this.activeScreen) {
        return SCREEN_ENTRIES[index].title;
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

  private async importManualConfig(): Promise<void> {
    const value = this.importBuffer.trim();
    if (value.length === 0) {
      this.lastError = '导入内容为空。';
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
    this.appendLog(`Setting changed: ${action}`);
  }

  private statusLabel(): string {
    switch (this.status) {
      case ConnectionStatus.STARTING:
        return 'Starting';
      case ConnectionStatus.RUNNING:
        return 'Running';
      case ConnectionStatus.STOPPING:
        return 'Stopping';
      case ConnectionStatus.ERROR:
        return 'Error';
      default:
        return 'Idle';
    }
  }

  private statusColor(): string {
    if (this.status === ConnectionStatus.RUNNING) {
      return '#166534';
    }
    if (this.status === ConnectionStatus.ERROR) {
      return '#B42318';
    }
    if (this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.STOPPING) {
      return '#92400E';
    }
    return '#374151';
  }

  private statusBackground(): string {
    if (this.status === ConnectionStatus.RUNNING) {
      return '#DCFCE7';
    }
    if (this.status === ConnectionStatus.ERROR) {
      return '#FEF3F2';
    }
    if (this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.STOPPING) {
      return '#FEF3C7';
    }
    return '#F3F4F6';
  }

  private isRunning(): boolean {
    return this.status === ConnectionStatus.RUNNING;
  }

  private isBusy(): boolean {
    return this.status === ConnectionStatus.STARTING || this.status === ConnectionStatus.STOPPING;
  }

  private formatBytes(value: number): string {
    if (value >= 1024 * 1024) {
      return `${(value / 1024 / 1024).toFixed(1)} MB`;
    }
    if (value >= 1024) {
      return `${(value / 1024).toFixed(1)} KB`;
    }
    return `${value} B`;
  }

  private formatTime(value: number): string {
    const date = new Date(value);
    return `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}:${this.pad2(date.getSeconds())}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}
