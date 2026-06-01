import { common } from '@kit.AbilityKit';
import { ConnectionStatus, ProxyNode, ProxyProfile, RuntimeStats } from '../core/Profile';
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
    Scroll() {
      Column({ space: 16 }) {
        this.StatusPanel()
        this.SubscriptionPanel()
        this.ConfigPanel()
        this.RuntimePanel()
        this.LogPanel()
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 28 })
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F6F8FA')
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
        Text('Subscription')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
        Text(`${this.nodes.length} nodes`)
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
        Button(this.subscriptionUpdating ? 'Updating' : 'Update')
          .height(38)
          .width(104)
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
      this.subscriptionUrl = subscription.url;
      this.nodes = subscription.nodes;
      this.selectedNodeId = subscription.selectedNodeId;
      this.subscriptionMessage = subscription.updatedAt > 0 ? `Updated ${this.formatTime(subscription.updatedAt)}` : 'No subscription loaded.';

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

    this.subscriptionUpdating = true;
    this.subscriptionMessage = 'Updating subscription.';
    this.appendLog('Updating subscription.');
    try {
      const context = getContext(this) as common.Context;
      await SubscriptionStore.saveUrl(context, this.subscriptionUrl.trim());
      const result: SubscriptionUpdateResult = await SubscriptionManager.fetchAndParse(this.subscriptionUrl);
      if (!result.ok) {
        this.subscriptionMessage = result.message;
        this.appendLog(result.message);
        return;
      }

      let selectedId = this.selectedNodeId;
      if (this.findNodeInList(result.nodes, selectedId) === null) {
        selectedId = result.nodes[0].id;
      }
      await SubscriptionStore.saveNodes(context, this.subscriptionUrl.trim(), result.nodes, selectedId);
      this.nodes = result.nodes;
      this.selectedNodeId = selectedId;
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

  private async selectNode(node: ProxyNode): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      await SubscriptionStore.selectNode(context, node.id);
      const profile = await ProfileStore.save(context, node.outboundJson);
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
