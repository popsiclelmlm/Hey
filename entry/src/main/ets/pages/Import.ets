import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { SelectionButton } from '../components/SelectionButton';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { XrayConfigPanel } from '../features/import/ConfigPanel';
import { NODES_CONTROLLER, NodesControllerState, SaveProfileResult } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SUBSCRIPTIONS_CONTROLLER } from '../features/subscriptions/SubscriptionsController';
import { AppRoute } from '../shell/AppRoute';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

interface FormVlessUser {
  id: string;
  encryption: string;
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

interface FormWsHeaders {
  Host: string;
}

interface FormWsSettings {
  path: string;
  headers: FormWsHeaders;
}

interface FormGrpcSettings {
  serviceName: string;
  authority: string;
}

interface FormHttpSettings {
  path: string;
  host: Array<string>;
}

interface FormStreamSettings {
  network: string;
  security?: string;
  wsSettings?: FormWsSettings;
  grpcSettings?: FormGrpcSettings;
  httpSettings?: FormHttpSettings;
}

type FormOutboundSettings = FormVlessSettings | FormVmessSettings | FormTrojanSettings | FormShadowsocksSettings | FormServerSettings;

interface FormOutbound {
  protocol: string;
  tag: string;
  settings?: FormOutboundSettings;
  streamSettings?: FormStreamSettings;
}

@Entry
@Component
struct ImportPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private outboundJson: string = '';
  @State private validationMessage: string = translate(DEFAULT_LANGUAGE, 'validation.initial');
  @State private validationOk: boolean = false;
  @State private profileUpdatedAt: string = translate(DEFAULT_LANGUAGE, 'profile.notSaved');
  @State private importBuffer: string = '';
  @State private selectedImportProtocol: string = 'vless';
  @State private lastError: string = '';
  @State private isBusy: boolean = false;
  @State private selectedNodeId: string = '';
  @State private nodeName: string = '';
  @State private serverHost: string = '';
  @State private serverPort: string = '443';
  @State private userIdOrPassword: string = '';
  @State private proxyUser: string = '';
  @State private proxyPass: string = '';
  @State private securityOrMethod: string = 'none';
  @State private vmessAlterId: string = '0';
  @State private transportType: string = 'tcp';
  @State private transportHost: string = '';
  @State private transportPath: string = '';
  @State private tlsSecurity: string = '';

  aboutToAppear(): void {
    this.applyProtocolDefaults(this.selectedImportProtocol);
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.import.title'),
        summary: this.validationMessage,
        showBack: true
      })
      Scroll() {
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

          this.ProtocolEditorCard()

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
              .enabled(!this.isBusy)
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

          if (this.lastError.length > 0) {
            Text(this.lastError)
              .fontSize(12)
              .fontColor('#B42318')
              .width('100%')
              .padding(10)
              .backgroundColor('#FEF3F2')
              .borderRadius(6)
          }

          this.ConfigPanel()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F6F8FA')
  }

  @Builder
  private ProtocolButton(protocol: string) {
    SelectionButton({
      label: protocol.toUpperCase(),
      itemValue: protocol,
      isSelected: this.selectedImportProtocol === protocol,
      labelSize: 11,
      onSelect: (value: string) => {
        this.selectedImportProtocol = value;
        this.applyProtocolDefaults(value);
      }
    })
  }

  @Builder
  private ProtocolEditorCard() {
    Column({ space: 8 }) {
      Text('协议参数编辑器')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .width('100%')
      Text('支持 VLESS / VMESS / TROJAN / SS / SOCKS / HTTP，点击“生成到导入区”后可直接导入')
        .fontSize(12)
        .fontColor('#6B7280')
        .width('100%')
      this.EditorRow('节点名', this.nodeName, (value: string) => {
        this.nodeName = value;
      })
      this.EditorRow('服务器', this.serverHost, (value: string) => {
        this.serverHost = value;
      })
      this.EditorRow('端口', this.serverPort, (value: string) => {
        this.serverPort = value;
      })
      if (this.selectedImportProtocol === 'vless' || this.selectedImportProtocol === 'vmess') {
        this.EditorRow('UUID', this.userIdOrPassword, (value: string) => {
          this.userIdOrPassword = value;
        })
      } else if (this.selectedImportProtocol === 'trojan' || this.selectedImportProtocol === 'ss') {
        this.EditorRow(this.selectedImportProtocol === 'trojan' ? '密码' : '加密密码', this.userIdOrPassword, (value: string) => {
          this.userIdOrPassword = value;
        })
      }
      if (this.selectedImportProtocol === 'socks' || this.selectedImportProtocol === 'http') {
        this.EditorRow('用户名(可选)', this.proxyUser, (value: string) => {
          this.proxyUser = value;
        })
        this.EditorRow('密码(可选)', this.proxyPass, (value: string) => {
          this.proxyPass = value;
        })
      }
      if (this.selectedImportProtocol === 'vless') {
        this.EditorRow('encryption', this.securityOrMethod, (value: string) => {
          this.securityOrMethod = value;
        })
      }
      if (this.selectedImportProtocol === 'vmess') {
        this.EditorRow('security', this.securityOrMethod, (value: string) => {
          this.securityOrMethod = value;
        })
        this.EditorRow('alterId', this.vmessAlterId, (value: string) => {
          this.vmessAlterId = value;
        })
      }
      if (this.selectedImportProtocol === 'ss') {
        this.EditorRow('method', this.securityOrMethod, (value: string) => {
          this.securityOrMethod = value;
        })
      }
      if (this.selectedImportProtocol === 'vless' || this.selectedImportProtocol === 'vmess' || this.selectedImportProtocol === 'trojan') {
        this.EditorRow('network(tcp/ws/grpc/h2)', this.transportType, (value: string) => {
          this.transportType = value;
        })
        this.EditorRow('host(可选)', this.transportHost, (value: string) => {
          this.transportHost = value;
        })
        this.EditorRow('path(可选)', this.transportPath, (value: string) => {
          this.transportPath = value;
        })
        this.EditorRow('security(tls/reality/空)', this.tlsSecurity, (value: string) => {
          this.tlsSecurity = value;
        })
      }
      Button('生成到导入区')
        .height(36)
        .width('100%')
        .backgroundColor('#1D4ED8')
        .fontColor('#FFFFFF')
        .borderRadius(6)
        .onClick(() => {
          this.generateProtocolOutbound();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }

  @Builder
  private EditorRow(label: string, value: string, onChange: (value: string) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#6B7280')
        .width(120)
      TextInput({ text: value, placeholder: label })
        .height(34)
        .layoutWeight(1)
        .fontSize(12)
        .backgroundColor('#F9FAFB')
        .borderRadius(6)
        .onChange((next: string) => {
          onChange(next);
        })
    }
    .width('100%')
  }

  @Builder
  private ConfigPanel() {
    XrayConfigPanel({
      title: this.t('config.title'),
      updatedAt: this.profileUpdatedAt,
      placeholder: this.t('placeholder.outbound'),
      outboundJson: this.outboundJson,
      validLabel: this.t('config.valid'),
      invalidLabel: this.t('config.invalid'),
      validationOk: this.validationOk,
      validationMessage: this.validationMessage,
      importLabel: this.t('action.import'),
      isBusy: this.isBusy,
      onConfigChange: (value: string) => {
        this.outboundJson = value;
        this.validateConfig();
      },
      onImport: () => {
        this.normalizeConfigInput();
      }
    })
  }

  private async loadState(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.language = (await SETTINGS_CONTROLLER.load(context)).language;
      this.applyNodesState(await NODES_CONTROLLER.load(context, this.language));
    } catch (error) {
      this.lastError = this.f1('error.loadProfile', 'error', JSON.stringify(error));
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
    }
  }

  private validateConfig(): void {
    const validation = NODES_CONTROLLER.validateConfig(this.outboundJson, this.language);
    this.validationOk = validation.valid;
    this.validationMessage = validation.message;
  }

  private normalizeConfigInput(): void {
    const validation = NODES_CONTROLLER.validateConfig(this.outboundJson, this.language);
    this.validationOk = validation.valid;
    this.validationMessage = validation.message;
    if (!validation.valid) {
      this.lastError = this.validationMessage;
      SHARED_RUNTIME_CONTROLLER.appendLog(this.validationMessage);
      return;
    }
    this.outboundJson = validation.normalizedJson;
    this.lastError = '';
    SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.configImported'));
  }

  private async importManualConfig(): Promise<void> {
    const value = this.importBuffer.trim();
    if (value.length === 0) {
      this.lastError = this.t('error.emptyImport');
      SHARED_RUNTIME_CONTROLLER.appendLog(this.lastError);
      return;
    }

    this.isBusy = true;
    try {
      if (value.toLowerCase().startsWith('http://') || value.toLowerCase().startsWith('https://')) {
        const context = getContext(this) as common.Context;
        const state = await SUBSCRIPTIONS_CONTROLLER.update(context, value, this.selectedNodeId, this.language);
        SHARED_RUNTIME_CONTROLLER.appendLog(state.subscriptionMessage);
        router.pushUrl({ url: AppRoute.SUBSCRIPTIONS });
        return;
      }

      this.outboundJson = value;
      this.normalizeConfigInput();
      if (!this.validationOk) {
        return;
      }
      const context = getContext(this) as common.Context;
      const saved = await NODES_CONTROLLER.saveProfile(context, this.outboundJson, this.language);
      this.applySaveProfileResult(saved);
      if (saved.profile !== null) {
        this.importBuffer = this.outboundJson;
        SHARED_RUNTIME_CONTROLLER.appendLog(this.t('log.profileSaved'));
        router.back();
      }
    } finally {
      this.isBusy = false;
    }
  }

  private generateProtocolOutbound(): void {
    const host = this.serverHost.trim();
    const port = Number(this.serverPort.trim());
    if (host.length === 0 || Number.isNaN(port) || port < 1 || port > 65535) {
      this.lastError = '请填写有效的服务器和端口';
      return;
    }

    const protocol = this.selectedImportProtocol;
    if (protocol !== 'vless' && protocol !== 'vmess' && protocol !== 'trojan' && protocol !== 'ss' && protocol !== 'socks' && protocol !== 'http') {
      this.lastError = '当前仅支持 VLESS/VMESS/TROJAN/SS/SOCKS/HTTP 表单生成';
      return;
    }

    const outbound: FormOutbound = {
      protocol: protocol === 'ss' ? 'shadowsocks' : protocol,
      tag: 'proxy'
    };

    if (protocol === 'vless') {
      const user: FormVlessUser = {
        id: this.userIdOrPassword.trim(),
        encryption: this.valueOr(this.securityOrMethod, 'none')
      };
      const server: FormVlessServer = {
        address: host,
        port: port,
        users: [user]
      };
      outbound.settings = {
        vnext: [server]
      } as FormVlessSettings;
    } else if (protocol === 'vmess') {
      const user: FormVmessUser = {
        id: this.userIdOrPassword.trim(),
        alterId: this.numberOr(this.vmessAlterId, 0),
        security: this.valueOr(this.securityOrMethod, 'auto')
      };
      const server: FormVmessServer = {
        address: host,
        port: port,
        users: [user]
      };
      outbound.settings = {
        vnext: [server]
      } as FormVmessSettings;
    } else if (protocol === 'trojan') {
      const server: FormTrojanServer = {
        address: host,
        port: port,
        password: this.userIdOrPassword.trim()
      };
      outbound.settings = {
        servers: [server]
      } as FormTrojanSettings;
    } else if (protocol === 'ss') {
      const server: FormShadowsocksServer = {
        address: host,
        port: port,
        method: this.valueOr(this.securityOrMethod, 'aes-128-gcm'),
        password: this.userIdOrPassword.trim()
      };
      outbound.settings = {
        servers: [server]
      } as FormShadowsocksSettings;
    } else if (protocol === 'socks' || protocol === 'http') {
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

    if (protocol === 'vless' || protocol === 'vmess' || protocol === 'trojan') {
      const network = this.valueOr(this.transportType, 'tcp').toLowerCase();
      const streamSettings: FormStreamSettings = {
        network: network
      };
      const security = this.tlsSecurity.trim().toLowerCase();
      if (security === 'tls' || security === 'reality') {
        streamSettings.security = security;
      }
      if (network === 'ws') {
        const headers: FormWsHeaders = {
          Host: this.transportHost.trim()
        };
        const wsSettings: FormWsSettings = {
          path: this.valueOr(this.transportPath, '/'),
          headers: headers
        };
        streamSettings.wsSettings = wsSettings;
      } else if (network === 'grpc') {
        const grpcSettings: FormGrpcSettings = {
          serviceName: this.transportPath.trim(),
          authority: this.transportHost.trim()
        };
        streamSettings.grpcSettings = grpcSettings;
      } else if (network === 'h2') {
        const hosts = new Array<string>();
        const transportHost = this.transportHost.trim();
        if (transportHost.length > 0) {
          hosts.push(transportHost);
        }
        const httpSettings: FormHttpSettings = {
          path: this.valueOr(this.transportPath, '/'),
          host: hosts
        };
        streamSettings.httpSettings = httpSettings;
      }
      outbound.streamSettings = streamSettings;
    }

    this.importBuffer = JSON.stringify(outbound, null, 2);
    this.outboundJson = this.importBuffer;
    this.normalizeConfigInput();
    this.lastError = '';
    SHARED_RUNTIME_CONTROLLER.appendLog('已从协议表单生成 outbound JSON');
  }

  private valueOr(value: string, fallback: string): string {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : fallback;
  }

  private numberOr(value: string, fallback: number): number {
    const parsed = Number(value.trim());
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return Math.floor(parsed);
  }

  private applyProtocolDefaults(protocol: string): void {
    if (protocol === 'vless') {
      this.serverPort = '443';
      this.securityOrMethod = 'none';
      this.transportType = 'tcp';
      this.tlsSecurity = '';
    } else if (protocol === 'vmess') {
      this.serverPort = '443';
      this.securityOrMethod = 'auto';
      this.vmessAlterId = '0';
      this.transportType = 'tcp';
      this.tlsSecurity = '';
    } else if (protocol === 'trojan') {
      this.serverPort = '443';
      this.transportType = 'tcp';
      this.tlsSecurity = 'tls';
    } else if (protocol === 'ss') {
      this.serverPort = '8388';
      this.securityOrMethod = 'aes-128-gcm';
      this.transportType = 'tcp';
      this.tlsSecurity = '';
    } else if (protocol === 'socks') {
      this.serverPort = '1080';
      this.transportType = 'tcp';
      this.tlsSecurity = '';
    } else if (protocol === 'http') {
      this.serverPort = '8080';
      this.transportType = 'tcp';
      this.tlsSecurity = '';
    }
  }

  private applyNodesState(state: NodesControllerState): void {
    this.outboundJson = state.outboundJson;
    this.validationOk = state.validationOk;
    this.validationMessage = state.validationMessage;
    this.profileUpdatedAt = state.profileUpdatedAt;
    this.selectedNodeId = state.selectedNodeId;
    this.lastError = state.lastError;
  }

  private applySaveProfileResult(result: SaveProfileResult): void {
    this.outboundJson = result.outboundJson;
    this.validationOk = result.validationOk;
    this.validationMessage = result.validationMessage;
    if (result.profile !== null) {
      this.profileUpdatedAt = result.profileUpdatedAt;
    }
    this.lastError = result.lastError;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
