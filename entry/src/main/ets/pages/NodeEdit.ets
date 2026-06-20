import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, formatTranslation, translate } from '../core/I18n';
import { buildV2rayNgH2HttpSettings } from '../core/H2Transport';
import { buildKcpFinalMask } from '../core/KcpTransport';
import { isManualEditProtocol, ManualOutboundEditState, normalizeManualEditProtocol, parseManualOutboundEditState } from '../core/ManualOutboundEditState';
import { buildManualHysteria2Outbound, buildManualWireguardOutbound } from '../core/ManualOutboundBuilder';
import { AppLanguage } from '../core/Profile';
import { markRuntimeSettingsRestartNeeded } from '../core/SettingsChange';
import { V2RAYNG_BROWSER_DIALER_MODE_OPTIONS, V2RAYNG_DEFAULT_BROWSER_DIALER_MODE, V2RAYNG_DEFAULT_VMESS_SECURITY, V2RAYNG_FLOW_OPTIONS, V2RAYNG_GRPC_MODE_OPTIONS, V2RAYNG_HYSTERIA2_SECURITY_OPTIONS, V2RAYNG_KCP_HEADER_TYPE_OPTIONS, V2RAYNG_SS_SECURITY_OPTIONS, V2RAYNG_STREAM_ALPN_OPTIONS, V2RAYNG_SUPPORTED_TRANSPORT_OPTIONS, V2RAYNG_TCP_HEADER_TYPE_OPTIONS, V2RAYNG_UTLS_FINGERPRINT_OPTIONS, V2RAYNG_VMESS_SECURITY_OPTIONS, V2RAYNG_XHTTP_MODE_OPTIONS, normalizeV2rayNgBrowserDialerMode, normalizeV2rayNgHysteria2Security, normalizeV2rayNgStreamAlpn, normalizeV2rayNgXhttpMode } from '../core/V2rayNgOptions';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

// 1. 声明独立的通用子组件，支持标准的双向状态重绘 (@Link)

@Component
struct SegmentedControl {
  @Prop label: string = '';
  options: Array<string> = [];
  @Link selected: string;
  onSelect?: (value: string) => void;

  build() {
    Column({ space: Space.sm }) {
      Text(this.label)
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textSecondary)
        .width('100%')
      Row({ space: Space.xs }) {
        ForEach(this.options, (option: string) => {
          Text(option.toUpperCase())
            .layoutWeight(1)
            .height(32)
            .fontSize(FontSz.caption)
            .fontWeight(this.selected === option ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.selected === option ? AppColor.onBrand : AppColor.textSecondary)
            .backgroundColor(this.selected === option ? AppColor.brand : Color.Transparent)
            .textAlign(TextAlign.Center)
            .borderRadius(Radius.sm)
            .onClick(() => {
              this.selected = option;
              if (this.onSelect !== undefined) {
                this.onSelect(option);
              }
            })
        }, (option: string) => option)
      }
      .width('100%')
      .padding(3)
      .backgroundColor(AppColor.surfaceAlt)
      .borderRadius(Radius.md)
    }
    .width('100%')
  }
}

@Component
struct ToggleRow {
  @Prop label: string = '';
  @Link isOn: boolean;

  build() {
    Row() {
      Text(this.label)
        .fontSize(FontSz.callout)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(AppColor.brand)
        .switchPointColor(AppColor.onBrand)
        .onChange((state: boolean) => {
          this.isOn = state;
        })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }
}

@Component
struct PickerRow {
  @Prop label: string = '';
  options: Array<string> = [];
  @Link selectedValue: string;

  build() {
    Column({ space: Space.sm }) {
      Text(this.label)
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textSecondary)
        .width('100%')

      Row() {
        Text(this.displayOption(this.selectedValue).toUpperCase())
          .fontSize(FontSz.body)
          .fontColor(AppColor.textPrimary)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Image($r('app.media.ic_chevron_right'))
          .width(18)
          .height(18)
          .fillColor(AppColor.textTertiary)
      }
      .width('100%')
      .height(44)
      .backgroundColor(AppColor.surfaceAlt)
      .borderRadius(Radius.md)
      .padding({ left: Space.md, right: Space.md })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        const selectedIndex = this.options.indexOf(this.selectedValue) >= 0 ? this.options.indexOf(this.selectedValue) : 0;
        TextPickerDialog.show({
          range: this.displayOptions(),
          selected: selectedIndex,
          onAccept: (value: TextPickerResult) => {
            let idx = 0;
            if (value.index !== undefined) {
              if (typeof value.index === 'number') {
                idx = value.index;
              } else if (typeof value.index === 'string') {
                idx = Number(value.index);
              } else if (Array.isArray(value.index)) {
                idx = Number(value.index[0]);
              }
            }
            if (!Number.isNaN(idx) && idx >= 0 && idx < this.options.length) {
              this.selectedValue = this.options[idx];
            } else if (value.value !== undefined) {
              if (typeof value.value === 'string') {
                this.selectedValue = this.optionForDisplay(value.value);
              } else if (Array.isArray(value.value)) {
                this.selectedValue = this.optionForDisplay(value.value[0]);
              }
            }
          }
        })
      })
    }
    .width('100%')
  }

  private displayOption(option: string): string {
    return option.length > 0 ? option : 'none';
  }

  private displayOptions(): Array<string> {
    const result = new Array<string>();
    for (let index = 0; index < this.options.length; index++) {
      result.push(this.displayOption(this.options[index]));
    }
    return result;
  }

  private optionForDisplay(value: string): string {
    for (let index = 0; index < this.options.length; index++) {
      if (this.displayOption(this.options[index]) === value) {
        return this.options[index];
      }
    }
    return value;
  }
}

// 2. 定义拼装 outbound JSON 结构所需的接口
interface FormVlessUser {
  id: string;
  encryption: string;
  flow?: string;
}

interface FormVlessServer {
  address: string;
  port: number;
  users: Array<FormVlessUser>;
}

interface FormVlessSettings {
  vnext: Array<FormVlessServer>;
}

interface FormVmessUser {
  id: string;
  alterId: number;
  security: string;
}

interface FormVmessServer {
  address: string;
  port: number;
  users: Array<FormVmessUser>;
}

interface FormVmessSettings {
  vnext: Array<FormVmessServer>;
}

interface FormTrojanServer {
  address: string;
  port: number;
  password: string;
  flow?: string;
}

interface FormTrojanSettings {
  servers: Array<FormTrojanServer>;
}

interface FormShadowsocksServer {
  address: string;
  port: number;
  method: string;
  password: string;
}

interface FormShadowsocksSettings {
  servers: Array<FormShadowsocksServer>;
}

interface FormGenericUser {
  user: string;
  pass: string;
}

interface FormGenericServer {
  address: string;
  port: number;
  users?: Array<FormGenericUser>;
}

interface FormServerSettings {
  servers: Array<FormGenericServer>;
}

interface FormWireguardPeer {
  publicKey: string;
  endpoint: string;
  preSharedKey?: string;
}

interface FormWireguardSettings {
  secretKey: string;
  address: Array<string>;
  peers: Array<FormWireguardPeer>;
  mtu?: number;
  reserved?: Array<number>;
}

interface FormHysteria2Server {
  address: string;
  port: number;
  password: string;
  security?: string;
  sni?: string;
  alpn?: string;
  insecure?: boolean;
  obfsPassword?: string;
  portHopping?: string;
  portHoppingInterval?: string;
  pinSHA256?: string;
  bandwidthDown?: string;
  bandwidthUp?: string;
}

interface FormHysteria2Settings {
  servers: Array<FormHysteria2Server>;
}

interface FormTcpRequest {
  path: Array<string>;
  headers: Record<string, Array<string>>;
}

interface FormTcpHeader {
  type: string;
  request?: FormTcpRequest;
}

interface FormTcpSettings {
  header: FormTcpHeader;
}

interface FormWsHeaders {
  Host: string;
}

interface FormWsSettings {
  path: string;
  headers: FormWsHeaders;
}

interface FormHttpUpgradeSettings {
  path: string;
  host: string;
}

interface FormKcpSettings {
  mtu?: number;
  tti?: number;
}

interface FormGrpcSettings {
  serviceName: string;
  authority: string;
  multiMode: boolean;
}

interface FormHttpSettings {
  path: string;
  host: Array<string>;
}

interface FormXhttpSettings {
  path: string;
  host: string;
  mode?: string;
  extra?: Object;
}

interface FormTlsSettings {
  allowInsecure: boolean;
  serverName?: string;
  alpn?: Array<string>;
  fingerprint?: string;
  echConfigList?: string;
  pinnedPeerCertSha256?: string;
  publicKey?: string;
  shortId?: string;
  spiderX?: string;
  mldsa65Verify?: string;
  show?: boolean;
}

interface FormStreamSettings {
  network: string;
  security?: string;
  tcpSettings?: FormTcpSettings;
  kcpSettings?: FormKcpSettings;
  wsSettings?: FormWsSettings;
  httpupgradeSettings?: FormHttpUpgradeSettings;
  grpcSettings?: FormGrpcSettings;
  httpSettings?: FormHttpSettings;
  xhttpSettings?: FormXhttpSettings;
  tlsSettings?: FormTlsSettings;
  realitySettings?: FormTlsSettings;
  finalmask?: Object;
}

type FormOutboundSettings = FormVlessSettings | FormVmessSettings | FormTrojanSettings | FormShadowsocksSettings | FormServerSettings | FormWireguardSettings | FormHysteria2Settings;

interface FormOutbound {
  protocol: string;
  tag: string;
  settings?: FormOutboundSettings;
  streamSettings?: FormStreamSettings;
  browserDialerMode?: string;
}

interface NodeEditParams {
  protocol?: string;
  nodeId?: string;
}

@Entry
@Component
struct NodeEditPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private protocol: string = 'vless';
  @State private nodeName: string = '';
  @State private serverHost: string = '';
  @State private serverPort: string = '443';
  @State private userIdOrPassword: string = '';
  @State private proxyUser: string = '';
  @State private proxyPass: string = '';
  @State private securityOrMethod: string = 'none';
  @State private vmessAlterId: string = '0';
  @State private vlessFlow: string = 'none';
  
  // 传输协议设置
  @State private transportType: string = 'tcp';
  @State private transportHost: string = '';
  @State private transportPath: string = '';
  @State private transportFinalMask: string = '';
  @State private transportTcpHeaderType: string = 'none';
  @State private transportKcpHeaderType: string = 'none';
  @State private transportKcpMtu: string = '';
  @State private transportKcpTti: string = '';
  @State private transportGrpcMode: string = 'gun';
  @State private transportXhttpMode: string = 'auto';
  @State private transportXhttpExtra: string = '';
  @State private browserDialerMode: string = V2RAYNG_DEFAULT_BROWSER_DIALER_MODE;
  
  // 安全传输层设置 (TLS / Reality)
  @State private tlsSecurity: string = 'none';
  @State private tlsSni: string = '';
  @State private tlsAlpn: string = '';
  @State private tlsAllowInsecure: boolean = false;
  @State private tlsFingerprint: string = 'none';
  @State private tlsEchConfigList: string = '';
  @State private tlsPinnedPeerCertSha256: string = '';
  
  // Reality 专属字段
  @State private realityPublicKey: string = '';
  @State private realityShortId: string = '';
  @State private realitySpiderX: string = '/';
  @State private realityMldsa65Verify: string = '';

  // WireGuard 专属字段
  @State private wgPublicKey: string = '';
  @State private wgPreSharedKey: string = '';
  @State private wgReserved: string = '0,0,0';
  @State private wgLocalAddress: string = '172.16.0.2/32';
  @State private wgMtu: string = '1420';

  // Hysteria2 专属字段
  @State private hy2ObfsPassword: string = '';
  @State private hy2PortHopping: string = '';
  @State private hy2PortHoppingInterval: string = '';
  @State private hy2PinSha256: string = '';
  @State private hy2BandwidthDown: string = '';
  @State private hy2BandwidthUp: string = '';

  @State private editNodeId: string = '';
  @State private selectedNodeId: string = '';
  @State private isBusy: boolean = false;
  @State private lastError: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as NodeEditParams;
    this.editNodeId = params?.nodeId ?? '';
    const requestedProtocol = normalizeManualEditProtocol(params?.protocol ?? 'vless');
    if (this.editNodeId.length === 0) {
      this.protocol = isManualEditProtocol(requestedProtocol) ? requestedProtocol : 'vless';
      this.applyProtocolDefaults(this.protocol);
    }
    this.loadState(requestedProtocol);
  }

  build() {
    Column() {
      PageHeader({
        title: this.tf('nodeEdit.titleWithProtocol', ['protocol'], [this.protocol.toUpperCase()]),
        showBack: true
      })

      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: Space.lg }) {
            // Card 1：基础配置信息
            SectionHeader({ title: this.t('nodeEdit.section.basic') })
            Column({ space: Space.md }) {
              this.EditorRow('nodeEdit.nodeName', this.nodeName, 'nodeEdit.nodeName.placeholder', (value: string) => {
                this.nodeName = value;
              })
              this.EditorRow(this.protocol === 'wireguard' ? 'nodeEdit.endpointHost' : 'nodeEdit.serverHost', this.serverHost, 'nodeEdit.host.placeholder', (value: string) => {
                this.serverHost = value;
              })
              this.EditorRow(this.protocol === 'wireguard' ? 'nodeEdit.endpointPort' : 'nodeEdit.serverPort', this.serverPort, 'nodeEdit.port.placeholder', (value: string) => {
                this.serverPort = value;
              })
            }
            .width('100%')
            .padding(Space.lg)
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .margin({ left: Space.lg, right: Space.lg })

            // Card 2：认证与加密参数
            SectionHeader({ title: this.t('nodeEdit.section.auth') })
            Column({ space: Space.md }) {

              // VLESS 与 VMess UUID
              if (this.protocol === 'vless' || this.protocol === 'vmess') {
                this.EditorRow('nodeEdit.uuid', this.userIdOrPassword, 'nodeEdit.uuid.placeholder', (value: string) => {
                  this.userIdOrPassword = value;
                })
              }
              // Trojan 连接密码
              else if (this.protocol === 'trojan') {
                this.EditorRow('nodeEdit.trojanPassword', this.userIdOrPassword, 'nodeEdit.trojanPassword.placeholder', (value: string) => {
                  this.userIdOrPassword = value;
                })
              }
              // Shadowsocks 密码
              else if (this.protocol === 'ss') {
                this.EditorRow('nodeEdit.ssPassword', this.userIdOrPassword, 'nodeEdit.ssPassword.placeholder', (value: string) => {
                  this.userIdOrPassword = value;
                })
              }
              // Hysteria2 密码
              else if (this.protocol === 'hysteria2') {
                this.EditorRow('nodeEdit.hy2Password', this.userIdOrPassword, 'nodeEdit.hy2Password.placeholder', (value: string) => {
                  this.userIdOrPassword = value;
                })
              }
              // WireGuard 本地私钥
              else if (this.protocol === 'wireguard') {
                this.EditorRow('nodeEdit.wgSecretKey', this.userIdOrPassword, 'nodeEdit.wgSecretKey.placeholder', (value: string) => {
                  this.userIdOrPassword = value;
                })
              }
              // Socks 与 HTTP 的用户名和密码
              else if (this.protocol === 'socks' || this.protocol === 'http') {
                this.EditorRow('nodeEdit.proxyUser', this.proxyUser, 'nodeEdit.proxyUser.placeholder', (value: string) => {
                  this.proxyUser = value;
                })
                this.EditorRow('nodeEdit.proxyPass', this.proxyPass, 'nodeEdit.proxyPass.placeholder', (value: string) => {
                  this.proxyPass = value;
                })
              }

              // 特有加密与流控选项
              if (this.protocol === 'vless') {
                this.EditorRow('nodeEdit.encryption', this.securityOrMethod, 'none', (value: string) => {
                  this.securityOrMethod = value;
                })
                PickerRow({
                  label: this.t('nodeEdit.flow'),
                  options: V2RAYNG_FLOW_OPTIONS,
                  selectedValue: $vlessFlow
                })
              } else if (this.protocol === 'vmess') {
                PickerRow({
                  label: this.t('nodeEdit.vmessSecurity'),
                  options: V2RAYNG_VMESS_SECURITY_OPTIONS,
                  selectedValue: $securityOrMethod
                })
                this.EditorRow('nodeEdit.alterId', this.vmessAlterId, 'nodeEdit.alterId.placeholder', (value: string) => {
                  this.vmessAlterId = value;
                })
              } else if (this.protocol === 'ss') {
                PickerRow({
                  label: this.t('nodeEdit.method'),
                  options: V2RAYNG_SS_SECURITY_OPTIONS,
                  selectedValue: $securityOrMethod
                })
              }
            }
            .width('100%')
            .padding(Space.lg)
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .margin({ left: Space.lg, right: Space.lg })

            // Card 3：WireGuard 专有配置
            if (this.protocol === 'wireguard') {
              SectionHeader({ title: this.t('nodeEdit.section.wireguard') })
              Column({ space: Space.md }) {
                this.EditorRow('nodeEdit.wgPublicKey', this.wgPublicKey, 'nodeEdit.wgPublicKey.placeholder', (value: string) => {
                  this.wgPublicKey = value;
                })
                this.EditorRow('nodeEdit.wgPreSharedKey', this.wgPreSharedKey, 'Pre-shared Key', (value: string) => {
                  this.wgPreSharedKey = value;
                })
                this.EditorRow('nodeEdit.wgLocalAddress', this.wgLocalAddress, 'nodeEdit.wgLocalAddress.placeholder', (value: string) => {
                  this.wgLocalAddress = value;
                })
                this.EditorRow('nodeEdit.wgReserved', this.wgReserved, 'nodeEdit.wgReserved.placeholder', (value: string) => {
                  this.wgReserved = value;
                })
                this.EditorRow('nodeEdit.wgMtu', this.wgMtu, 'nodeEdit.default1420', (value: string) => {
                  this.wgMtu = value;
                })
              }
              .width('100%')
              .padding(Space.lg)
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .margin({ left: Space.lg, right: Space.lg })
            }

            // Card 4：Hysteria2 专有配置
            if (this.protocol === 'hysteria2') {
              SectionHeader({ title: this.t('nodeEdit.section.hysteria2') })
              Column({ space: Space.md }) {
                this.EditorRow('nodeEdit.hy2ObfsPassword', this.hy2ObfsPassword, 'nodeEdit.hy2ObfsPassword.placeholder', (value: string) => {
                  this.hy2ObfsPassword = value;
                })
                this.EditorRow('nodeEdit.hy2PortHopping', this.hy2PortHopping, 'nodeEdit.hy2PortHopping.placeholder', (value: string) => {
                  this.hy2PortHopping = value;
                })
                this.EditorRow('nodeEdit.hy2PortHoppingInterval', this.hy2PortHoppingInterval, 'nodeEdit.hy2PortHoppingInterval.placeholder', (value: string) => {
                  this.hy2PortHoppingInterval = value;
                })
                this.EditorRow('nodeEdit.hy2BandwidthDown', this.hy2BandwidthDown, 'nodeEdit.hy2BandwidthDown.placeholder', (value: string) => {
                  this.hy2BandwidthDown = value;
                })
                this.EditorRow('nodeEdit.hy2BandwidthUp', this.hy2BandwidthUp, 'nodeEdit.hy2BandwidthUp.placeholder', (value: string) => {
                  this.hy2BandwidthUp = value;
                })

                PickerRow({
                  label: this.t('nodeEdit.hy2Security'),
                  options: V2RAYNG_HYSTERIA2_SECURITY_OPTIONS,
                  selectedValue: $tlsSecurity
                })

                // Hysteria 2 的 TLS 配置
                if (this.tlsSecurity === 'tls') {
                  this.EditorRow('nodeEdit.sni', this.tlsSni, 'nodeEdit.sni.placeholder', (value: string) => {
                    this.tlsSni = value;
                  })
                  this.EditorRow('nodeEdit.hy2PinSha256', this.hy2PinSha256, 'nodeEdit.hy2PinSha256.placeholder', (value: string) => {
                    this.hy2PinSha256 = value;
                  })
                  ToggleRow({
                    label: this.t('nodeEdit.allowInsecure'),
                    isOn: $tlsAllowInsecure
                  })
                }
              }
              .width('100%')
              .padding(Space.lg)
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .margin({ left: Space.lg, right: Space.lg })
            }

            // Card 5：流媒体与传输混淆设置 (适用于 VLESS, VMess, Trojan, SS)
            if (this.protocol === 'vless' || this.protocol === 'vmess' || this.protocol === 'trojan' || this.protocol === 'ss') {
              SectionHeader({ title: this.t('nodeEdit.section.transport') })
              Column({ space: Space.md }) {
                PickerRow({
                  label: this.t('nodeEdit.transportNetwork'),
                  options: V2RAYNG_SUPPORTED_TRANSPORT_OPTIONS,
                  selectedValue: $transportType
                })
                if (this.transportType === 'tcp') {
                  PickerRow({
                    label: this.t('nodeEdit.tcpHeaderType'),
                    options: V2RAYNG_TCP_HEADER_TYPE_OPTIONS,
                    selectedValue: $transportTcpHeaderType
                  })
                }
                if (this.transportType === 'kcp') {
                  PickerRow({
                    label: this.t('nodeEdit.kcpHeaderType'),
                    options: V2RAYNG_KCP_HEADER_TYPE_OPTIONS,
                    selectedValue: $transportKcpHeaderType
                  })
                  this.EditorRow('nodeEdit.kcpDnsHost', this.transportHost, 'nodeEdit.kcpDnsHost.placeholder', (value: string) => {
                    this.transportHost = value;
                  })
                  this.EditorRow('nodeEdit.kcpSeed', this.transportPath, 'nodeEdit.kcpSeed.placeholder', (value: string) => {
                    this.transportPath = value;
                  })
                  this.EditorRow('nodeEdit.kcpMtu', this.transportKcpMtu, 'nodeEdit.default1350', (value: string) => {
                    this.transportKcpMtu = value;
                  })
                  this.EditorRow('nodeEdit.kcpTti', this.transportKcpTti, 'nodeEdit.default50', (value: string) => {
                    this.transportKcpTti = value;
                  })
                } else {
                  this.EditorRow('nodeEdit.transportHost', this.transportHost, 'nodeEdit.transportHost.placeholder', (value: string) => {
                    this.transportHost = value;
                  })
                  this.EditorRow('nodeEdit.transportPath', this.transportPath, 'nodeEdit.transportPath.placeholder', (value: string) => {
                    this.transportPath = value;
                  })
                }
                if (this.transportType === 'grpc') {
                  PickerRow({
                    label: this.t('nodeEdit.grpcMode'),
                    options: V2RAYNG_GRPC_MODE_OPTIONS,
                    selectedValue: $transportGrpcMode
                  })
                }
                if (this.transportType === 'xhttp') {
                  PickerRow({
                    label: this.t('nodeEdit.xhttpMode'),
                    options: V2RAYNG_XHTTP_MODE_OPTIONS,
                    selectedValue: $transportXhttpMode
                  })
                  this.EditorRow('nodeEdit.xhttpExtra', this.transportXhttpExtra, '{ "headers": {} }', (value: string) => {
                    this.transportXhttpExtra = value;
                  })
                }
                if (this.transportType === 'ws' || this.transportType === 'xhttp') {
                  PickerRow({
                    label: this.t('nodeEdit.browserDialer'),
                    options: V2RAYNG_BROWSER_DIALER_MODE_OPTIONS,
                    selectedValue: $browserDialerMode
                  })
                }
                this.EditorRow('nodeEdit.finalMask', this.transportFinalMask, '{ "tcp": [], "udp": [] }', (value: string) => {
                  this.transportFinalMask = value;
                })

                // 排除 Shadowsocks（xray 协议规范中 Shadowsocks 通常不配置外层 TLS/Reality）
                if (this.protocol !== 'ss') {
                  SegmentedControl({
                    label: this.t('nodeEdit.security'),
                    options: this.protocol === 'trojan' ? ['tls', 'reality'] : ['none', 'tls', 'reality'],
                    selected: $tlsSecurity
                  })

                  // TLS 展开项
                  if (this.tlsSecurity === 'tls') {
                    this.EditorRow('nodeEdit.sni', this.tlsSni, 'nodeEdit.sni.placeholder', (value: string) => {
                      this.tlsSni = value;
                    })
                    PickerRow({
                      label: this.t('nodeEdit.alpn'),
                      options: V2RAYNG_STREAM_ALPN_OPTIONS,
                      selectedValue: $tlsAlpn
                    })
                    this.EditorRow('nodeEdit.ech', this.tlsEchConfigList, 'nodeEdit.ech.placeholder', (value: string) => {
                      this.tlsEchConfigList = value;
                    })
                    this.EditorRow('nodeEdit.pinnedSha256', this.tlsPinnedPeerCertSha256, 'nodeEdit.pinnedSha256.placeholder', (value: string) => {
                      this.tlsPinnedPeerCertSha256 = value;
                    })
                    ToggleRow({
                      label: this.t('nodeEdit.allowInsecure'),
                      isOn: $tlsAllowInsecure
                    })
                    PickerRow({
                      label: this.t('nodeEdit.fingerprint'),
                      options: V2RAYNG_UTLS_FINGERPRINT_OPTIONS,
                      selectedValue: $tlsFingerprint
                    })
                  }
                  // Reality 展开项
                  else if (this.tlsSecurity === 'reality') {
                    this.EditorRow('nodeEdit.realitySni', this.tlsSni, 'nodeEdit.realitySni.placeholder', (value: string) => {
                      this.tlsSni = value;
                    })
                    this.EditorRow('nodeEdit.ech', this.tlsEchConfigList, 'nodeEdit.ech.placeholder', (value: string) => {
                      this.tlsEchConfigList = value;
                    })
                    this.EditorRow('nodeEdit.pinnedSha256', this.tlsPinnedPeerCertSha256, 'nodeEdit.pinnedSha256.placeholder', (value: string) => {
                      this.tlsPinnedPeerCertSha256 = value;
                    })
                    this.EditorRow('nodeEdit.realityPublicKey', this.realityPublicKey, 'nodeEdit.realityPublicKey.placeholder', (value: string) => {
                      this.realityPublicKey = value;
                    })
                    this.EditorRow('nodeEdit.realityShortId', this.realityShortId, 'nodeEdit.realityShortId.placeholder', (value: string) => {
                      this.realityShortId = value;
                    })
                    this.EditorRow('nodeEdit.realityPath', this.realitySpiderX, 'nodeEdit.realityPath.placeholder', (value: string) => {
                      this.realitySpiderX = value;
                    })
                    this.EditorRow('nodeEdit.mldsa65Verify', this.realityMldsa65Verify, 'nodeEdit.mldsa65Verify.placeholder', (value: string) => {
                      this.realityMldsa65Verify = value;
                    })
                    PickerRow({
                      label: this.t('nodeEdit.fingerprint'),
                      options: V2RAYNG_UTLS_FINGERPRINT_OPTIONS,
                      selectedValue: $tlsFingerprint
                    })
                  }
                }
              }
              .width('100%')
              .padding(Space.lg)
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .margin({ left: Space.lg, right: Space.lg })
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
          .padding({ top: Space.sm, bottom: 100 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)

        // 底部保存按钮
        Column() {
          Button() {
            Row() {
              if (this.isBusy) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColor.onBrand)
                  .margin({ right: Space.sm })
              }
              Text(this.editNodeId.length > 0 ? this.t('nodeEdit.updateButton') : this.t('nodeEdit.saveButton'))
                .fontSize(FontSz.headline)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isSaveEnabled() ? AppColor.onBrand : AppColor.textTertiary)
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(Radius.pill)
          .enabled(this.isSaveEnabled())
          .backgroundColor(this.isSaveEnabled() ? AppColor.brand : AppColor.surfaceAlt)
          .onClick(() => {
            this.saveManualNode();
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.xxl })
        .backgroundColor(AppColor.bg)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private EditorRow(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: Space.sm }) {
      Text(this.resolveEditorText(label))
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textSecondary)
        .width('100%')
      TextInput({ text: value, placeholder: this.resolveEditorText(placeholder) })
        .height(44)
        .fontSize(FontSz.body)
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .backgroundColor(AppColor.surfaceAlt)
        .borderRadius(Radius.md)
        .padding({ left: Space.md, right: Space.md })
        .onChange((next: string) => {
          onChange(next);
        })
    }
    .width('100%')
  }

  private resolveEditorText(value: string): string {
    return value.startsWith('nodeEdit.') ? this.t(value) : value;
  }

  private isSaveEnabled(): boolean {
    return this.serverHost.trim().length > 0 && this.serverPort.trim().length > 0 && !this.isBusy;
  }

  private async loadState(requestedProtocol: string): Promise<void> {
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    if (this.editNodeId.length === 0) {
      return;
    }

    const state = await NODES_CONTROLLER.load(context, this.language);
    this.selectedNodeId = state.selectedNodeId;
    const found = NODES_CONTROLLER.findNode(state.nodes, this.editNodeId);
    if (found === null ||
      found.sourceUrl.trim().length > 0 ||
      found.rawLink.trim().length > 0 ||
      ((found.configType ?? 'outbound') !== 'outbound')) {
      this.lastError = translate(this.language, 'error.editManualNodeUnsupported');
      this.protocol = isManualEditProtocol(requestedProtocol) ? requestedProtocol : 'vless';
      this.applyProtocolDefaults(this.protocol);
      return;
    }

    const editState = parseManualOutboundEditState(found.outboundJson, found.name, found.protocol);
    if (!editState.valid) {
      this.lastError = editState.message;
      this.protocol = isManualEditProtocol(requestedProtocol) ? requestedProtocol : 'vless';
      this.applyProtocolDefaults(this.protocol);
      return;
    }
    this.applyManualEditState(editState);
  }

  private async saveManualNode(): Promise<void> {
    const host = this.serverHost.trim();
    const port = Number(this.serverPort.trim());
    if (host.length === 0 || Number.isNaN(port) || port < 1 || port > 65535) {
      this.lastError = this.t('nodeEdit.invalidServerPort');
      return;
    }

    this.isBusy = true;
    try {
      // 1. 初始化 outbound 基础字段
      const outbound: FormOutbound = {
        protocol: this.protocol === 'ss' ? 'shadowsocks' : this.protocol,
        tag: this.nodeName.trim().length > 0 ? this.nodeName.trim() : 'proxy'
      };

      // 2. 根据协议填充 settings 字段
      if (this.protocol === 'vless') {
        const user: FormVlessUser = {
          id: this.userIdOrPassword.trim(),
          encryption: this.valueOr(this.securityOrMethod, 'none')
        };
        if (this.vlessFlow.trim().length > 0 && this.vlessFlow.trim() !== 'none') {
          user.flow = this.vlessFlow.trim();
        }
        const server: FormVlessServer = {
          address: host,
          port: port,
          users: [user]
        };
        outbound.settings = {
          vnext: [server]
        } as FormVlessSettings;
      } 
      else if (this.protocol === 'vmess') {
        const user: FormVmessUser = {
          id: this.userIdOrPassword.trim(),
          alterId: this.numberOr(this.vmessAlterId, 0),
          security: this.valueOr(this.securityOrMethod, V2RAYNG_DEFAULT_VMESS_SECURITY)
        };
        const server: FormVmessServer = {
          address: host,
          port: port,
          users: [user]
        };
        outbound.settings = {
          vnext: [server]
        } as FormVmessSettings;
      } 
      else if (this.protocol === 'trojan') {
        const server: FormTrojanServer = {
          address: host,
          port: port,
          password: this.userIdOrPassword.trim()
        };
        if (this.vlessFlow.trim().length > 0 && this.vlessFlow.trim() !== 'none') {
          server.flow = this.vlessFlow.trim();
        }
        outbound.settings = {
          servers: [server]
        } as FormTrojanSettings;
      } 
      else if (this.protocol === 'ss') {
        const server: FormShadowsocksServer = {
          address: host,
          port: port,
          method: this.valueOr(this.securityOrMethod, 'aes-128-gcm'),
          password: this.userIdOrPassword.trim()
        };
        outbound.settings = {
          servers: [server]
        } as FormShadowsocksSettings;
      } 
      else if (this.protocol === 'socks' || this.protocol === 'http') {
        const server: FormGenericServer = {
          address: host,
          port: port
        };
        const user = this.proxyUser.trim();
        const pass = this.proxyPass.trim();
        if (user.length > 0 || pass.length > 0) {
          const account: FormGenericUser = {
            user: user,
            pass: pass
          };
          server.users = [account];
        }
        outbound.settings = {
          servers: [server]
        } as FormServerSettings;
      }
      else if (this.protocol === 'wireguard') {
        const built = buildManualWireguardOutbound({
          tag: outbound.tag,
          host,
          port: this.serverPort,
          secretKey: this.userIdOrPassword,
          publicKey: this.wgPublicKey,
          preSharedKey: this.wgPreSharedKey,
          localAddress: this.wgLocalAddress,
          reserved: this.wgReserved,
          mtu: this.wgMtu
        });
        if (!built.success) {
          this.lastError = built.message;
          return;
        }
        outbound.settings = (JSON.parse(built.outboundJson) as FormOutbound).settings;
      }
      else if (this.protocol === 'hysteria2') {
        const built = buildManualHysteria2Outbound({
          tag: outbound.tag,
          host,
          port: this.serverPort,
          password: this.userIdOrPassword,
          security: normalizeV2rayNgHysteria2Security(this.tlsSecurity),
          sni: this.tlsSni,
          alpn: this.tlsAlpn,
          allowInsecure: this.tlsAllowInsecure,
          obfsPassword: this.hy2ObfsPassword,
          portHopping: this.hy2PortHopping,
          portHoppingInterval: this.hy2PortHoppingInterval,
          pinSHA256: this.hy2PinSha256,
          bandwidthDown: this.hy2BandwidthDown,
          bandwidthUp: this.hy2BandwidthUp
        });
        if (!built.success) {
          this.lastError = built.message;
          return;
        }
        outbound.settings = (JSON.parse(built.outboundJson) as FormOutbound).settings;
      }

      // 3. 填充 streamSettings (适用于 VLESS, VMess, Trojan, SS)
      if (this.protocol === 'vless' || this.protocol === 'vmess' || this.protocol === 'trojan' || this.protocol === 'ss') {
        const network = this.valueOr(this.transportType, 'tcp').toLowerCase();
        const streamSettings: FormStreamSettings = {
          network: network
        };

        // Shadowsocks 忽略 TLS / Reality 安全选项
        if (this.protocol !== 'ss') {
          const security = this.tlsSecurity.trim().toLowerCase();
          if (security === 'tls' || security === 'reality') {
            streamSettings.security = security;
            
            const tlsConfig: FormTlsSettings = {
              allowInsecure: this.tlsAllowInsecure
            };
            if (this.tlsSni.trim().length > 0) {
              tlsConfig.serverName = this.tlsSni.trim();
            }
            const normalizedAlpn = normalizeV2rayNgStreamAlpn(this.tlsAlpn);
            if (normalizedAlpn.length > 0) {
              tlsConfig.alpn = normalizedAlpn.split(',').map(s => s.trim()).filter(s => s.length > 0);
            }
            if (this.tlsFingerprint.trim().length > 0 && this.tlsFingerprint.trim() !== 'none') {
              tlsConfig.fingerprint = this.tlsFingerprint.trim();
            }
            if (this.tlsEchConfigList.trim().length > 0) {
              tlsConfig.echConfigList = this.tlsEchConfigList.trim();
            }
            if (this.tlsPinnedPeerCertSha256.trim().length > 0) {
              tlsConfig.pinnedPeerCertSha256 = this.tlsPinnedPeerCertSha256.trim();
            }

            if (security === 'tls') {
              streamSettings.tlsSettings = tlsConfig;
            } else {
              tlsConfig.publicKey = this.realityPublicKey.trim();
              tlsConfig.shortId = this.realityShortId.trim();
              tlsConfig.spiderX = this.realitySpiderX.trim();
              if (this.realityMldsa65Verify.trim().length > 0) {
                tlsConfig.mldsa65Verify = this.realityMldsa65Verify.trim();
              }
              tlsConfig.show = false;
              streamSettings.realitySettings = tlsConfig;
            }
          }
        }

        // 填充底层传输协议专属配置
        if (network === 'tcp') {
          const tcpHeader: FormTcpHeader = {
            type: this.transportTcpHeaderType === 'http' ? 'http' : 'none'
          };
          if (tcpHeader.type === 'http') {
            const headers: Record<string, Array<string>> = {};
            headers['Host'] = this.splitCsv(this.transportHost);
            tcpHeader.request = {
              path: this.splitCsvWithDefault(this.transportPath, '/'),
              headers
            };
          }
          streamSettings.tcpSettings = {
            header: tcpHeader
          };
        }
        else if (network === 'kcp') {
          const kcpSettings: FormKcpSettings = {};
          const mtu = this.optionalPositiveInteger(this.transportKcpMtu);
          if (mtu < 0) {
            this.lastError = this.t('nodeEdit.kcpMtuPositive');
            return;
          }
          const tti = this.optionalPositiveInteger(this.transportKcpTti);
          if (tti < 0) {
            this.lastError = this.t('nodeEdit.kcpTtiPositive');
            return;
          }
          if (mtu > 0) {
            kcpSettings.mtu = mtu;
          }
          if (tti > 0) {
            kcpSettings.tti = tti;
          }
          streamSettings.kcpSettings = kcpSettings;
          streamSettings.finalmask = buildKcpFinalMask(this.transportKcpHeaderType, this.transportHost, this.transportPath);
        }
        else if (network === 'ws') {
          const wsHeaders: FormWsHeaders = {
            Host: this.transportHost.trim()
          };
          const wsSettings: FormWsSettings = {
            path: this.valueOr(this.transportPath, '/'),
            headers: wsHeaders
          };
          streamSettings.wsSettings = wsSettings;
        } 
        else if (network === 'httpupgrade') {
          const httpUpgradeSettings: FormHttpUpgradeSettings = {
            path: this.valueOr(this.transportPath, '/'),
            host: this.transportHost.trim()
          };
          streamSettings.httpupgradeSettings = httpUpgradeSettings;
        }
        else if (network === 'grpc') {
          const grpcSettings: FormGrpcSettings = {
            serviceName: this.transportPath.trim(),
            authority: this.transportHost.trim(),
            multiMode: this.transportGrpcMode === 'multi'
          };
          streamSettings.grpcSettings = grpcSettings;
        } 
        else if (network === 'h2') {
          const h2Settings = buildV2rayNgH2HttpSettings(this.transportHost, this.transportPath);
          const httpSettings: FormHttpSettings = {
            path: h2Settings.path,
            host: h2Settings.host
          };
          streamSettings.httpSettings = httpSettings;
        }
        else if (network === 'xhttp') {
          const xhttpSettings: FormXhttpSettings = {
            path: this.valueOr(this.transportPath, '/'),
            host: this.transportHost.trim(),
            mode: normalizeV2rayNgXhttpMode(this.transportXhttpMode)
          };
          const xhttpExtraText = this.transportXhttpExtra.trim();
          if (xhttpExtraText.length > 0) {
            try {
              const extra = JSON.parse(xhttpExtraText) as Object;
              if (extra === null || typeof extra !== 'object') {
                this.lastError = this.t('nodeEdit.xhttpExtraObject');
                return;
              }
              xhttpSettings.extra = extra;
            } catch (error) {
              this.lastError = this.tf('nodeEdit.xhttpExtraParseFailed', ['error'], [JSON.stringify(error)]);
              return;
            }
          }
          streamSettings.xhttpSettings = xhttpSettings;
        }

        const finalMaskText = this.transportFinalMask.trim();
        if (finalMaskText.length > 0) {
          try {
            const finalMask = JSON.parse(finalMaskText) as Object;
            if (finalMask === null || typeof finalMask !== 'object') {
              this.lastError = this.t('nodeEdit.finalMaskObject');
              return;
            }
            streamSettings.finalmask = finalMask;
          } catch (error) {
            this.lastError = this.tf('nodeEdit.finalMaskParseFailed', ['error'], [JSON.stringify(error)]);
            return;
          }
        }
        
        outbound.streamSettings = streamSettings;
        if (network === 'ws' || network === 'xhttp') {
          const mode = normalizeV2rayNgBrowserDialerMode(this.browserDialerMode);
          if (mode !== V2RAYNG_DEFAULT_BROWSER_DIALER_MODE) {
            outbound.browserDialerMode = mode;
          }
        }
      }

      // 4. 进行校验与保存
      const outboundJson = JSON.stringify(outbound, null, 2);
      const context = getContext(this) as common.Context;
      
      const validation = NODES_CONTROLLER.validateConfig(outboundJson, this.language);
      if (!validation.valid) {
        this.lastError = validation.message;
        return;
      }

      if (this.editNodeId.length > 0) {
        const updated = await NODES_CONTROLLER.updateManualNode(context, this.editNodeId, this.nodeName, validation.normalizedJson, this.language, validation.configType);
        if (!updated.success) {
          this.lastError = updated.lastError;
          return;
        }
        if (updated.selected || this.editNodeId === this.selectedNodeId) {
          markRuntimeSettingsRestartNeeded();
        }
        promptAction.showToast({ message: this.t('nodeEdit.updated') });
      } else {
        const saved = await NODES_CONTROLLER.saveProfile(context, validation.normalizedJson, this.language, validation.configType);
        if (saved.profile === null) {
          this.lastError = saved.lastError;
          return;
        }

        await SubscriptionStore.addManualNode(context, this.nodeName, validation.normalizedJson, validation.configType);
        markRuntimeSettingsRestartNeeded();
        promptAction.showToast({ message: this.t('nodeEdit.saved') });
      }
      router.back();
    } catch (error) {
      this.lastError = this.tf('nodeEdit.saveFailed', ['error'], [JSON.stringify(error)]);
    } finally {
      this.isBusy = false;
    }
  }

  private valueOr(value: string, fallback: string): string {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : fallback;
  }

  private splitCsv(value: string): Array<string> {
    return value.split(',').map(item => item.trim()).filter(item => item.length > 0);
  }

  private splitCsvWithDefault(value: string, fallback: string): Array<string> {
    const result = this.splitCsv(value);
    if (result.length === 0) {
      result.push(fallback);
    }
    return result;
  }

  private numberOr(value: string, fallback: number): number {
    const parsed = Number(value.trim());
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return Math.floor(parsed);
  }

  private optionalPositiveInteger(value: string): number {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      return 0;
    }
    const parsed = Number(trimmed);
    if (Number.isNaN(parsed) || parsed <= 0 || Math.floor(parsed) !== parsed) {
      return -1;
    }
    return parsed;
  }

  private applyProtocolDefaults(protocol: string): void {
    if (protocol === 'vless') {
      this.serverPort = '443';
      this.securityOrMethod = 'none';
      this.transportType = 'tcp';
      this.browserDialerMode = V2RAYNG_DEFAULT_BROWSER_DIALER_MODE;
      this.tlsSecurity = 'reality';
      this.tlsFingerprint = 'chrome';
      this.vlessFlow = 'xtls-rprx-vision';
    } else if (protocol === 'vmess') {
      this.serverPort = '443';
      this.securityOrMethod = V2RAYNG_DEFAULT_VMESS_SECURITY;
      this.vmessAlterId = '0';
      this.transportType = 'tcp';
      this.browserDialerMode = V2RAYNG_DEFAULT_BROWSER_DIALER_MODE;
      this.tlsSecurity = 'tls';
      this.tlsFingerprint = 'chrome';
    } else if (protocol === 'trojan') {
      this.serverPort = '443';
      this.transportType = 'tcp';
      this.browserDialerMode = V2RAYNG_DEFAULT_BROWSER_DIALER_MODE;
      this.tlsSecurity = 'tls';
      this.tlsFingerprint = 'chrome';
    } else if (protocol === 'ss') {
      this.serverPort = '8388';
      this.securityOrMethod = 'aes-128-gcm';
      this.transportType = 'tcp';
      this.browserDialerMode = V2RAYNG_DEFAULT_BROWSER_DIALER_MODE;
      this.tlsSecurity = 'none';
    } else if (protocol === 'socks') {
      this.serverPort = '1080';
      this.tlsSecurity = 'none';
    } else if (protocol === 'http') {
      this.serverPort = '8080';
      this.tlsSecurity = 'none';
    } else if (protocol === 'wireguard') {
      this.serverPort = '51820';
      this.tlsSecurity = 'none';
    } else if (protocol === 'hysteria2') {
      this.serverPort = '443';
      this.tlsSecurity = 'tls';
      this.tlsAlpn = 'h3';
    }
  }

  private applyManualEditState(state: ManualOutboundEditState): void {
    this.protocol = state.protocol;
    this.nodeName = state.nodeName;
    this.serverHost = state.serverHost;
    this.serverPort = state.serverPort;
    this.userIdOrPassword = state.userIdOrPassword;
    this.proxyUser = state.proxyUser;
    this.proxyPass = state.proxyPass;
    this.securityOrMethod = state.securityOrMethod;
    this.vmessAlterId = state.vmessAlterId;
    this.vlessFlow = state.vlessFlow;
    this.transportType = state.transportType;
    this.transportHost = state.transportHost;
    this.transportPath = state.transportPath;
    this.transportFinalMask = state.transportFinalMask;
    this.transportTcpHeaderType = state.transportTcpHeaderType;
    this.transportKcpHeaderType = state.transportKcpHeaderType;
    this.transportKcpMtu = state.transportKcpMtu;
    this.transportKcpTti = state.transportKcpTti;
    this.transportGrpcMode = state.transportGrpcMode;
    this.transportXhttpMode = state.transportXhttpMode;
    this.transportXhttpExtra = state.transportXhttpExtra;
    this.browserDialerMode = state.browserDialerMode;
    this.tlsSecurity = state.tlsSecurity;
    this.tlsSni = state.tlsSni;
    this.tlsAlpn = state.tlsAlpn;
    this.tlsAllowInsecure = state.tlsAllowInsecure;
    this.tlsFingerprint = state.tlsFingerprint;
    this.tlsEchConfigList = state.tlsEchConfigList;
    this.tlsPinnedPeerCertSha256 = state.tlsPinnedPeerCertSha256;
    this.realityPublicKey = state.realityPublicKey;
    this.realityShortId = state.realityShortId;
    this.realitySpiderX = state.realitySpiderX;
    this.realityMldsa65Verify = state.realityMldsa65Verify;
    this.wgPublicKey = state.wgPublicKey;
    this.wgPreSharedKey = state.wgPreSharedKey;
    this.wgReserved = state.wgReserved;
    this.wgLocalAddress = state.wgLocalAddress;
    this.wgMtu = state.wgMtu;
    this.hy2ObfsPassword = state.hy2ObfsPassword;
    this.hy2PortHopping = state.hy2PortHopping;
    this.hy2PortHoppingInterval = state.hy2PortHoppingInterval;
    this.hy2PinSha256 = state.hy2PinSha256;
    this.hy2BandwidthDown = state.hy2BandwidthDown;
    this.hy2BandwidthUp = state.hy2BandwidthUp;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private tf(key: string, names: Array<string>, values: Array<string>): string {
    return formatTranslation(this.language, key, names, values);
  }
}
