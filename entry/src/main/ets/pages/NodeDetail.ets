import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, AppSettings, ProxyNode, SubscriptionGroup } from '../core/Profile';
import { formatOutboundJsonToShareLink } from '../core/ShareLinkParser';
import { isManualEditProtocol, normalizeManualEditProtocol } from '../core/ManualOutboundEditState';
import { buildNodeFullConfigModel, NodeFullConfigModel } from '../features/nodes/NodeOperations';
import { buildNodeDetailSections, NodeDetailField, NodeDetailSection } from '../features/nodes/NodeDetailFields';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { DEFAULT_APP_SETTINGS } from '../storage/SettingsStore';
import { PageHeader } from '../shell/PageHeader';
import { AppRoute } from '../shell/AppRoute';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

interface NodeDetailParams {
  nodeId?: string;
}

const EMPTY_NODE: ProxyNode = {
  id: '',
  name: '',
  protocol: '',
  outboundJson: '',
  sourceUrl: '',
  rawLink: '',
  updatedAt: 0,
  delayMs: 0,
  delayTestAt: 0,
  delayStatus: ''
};

const MASK_TEXT: string = '••••••••';
const CONFIG_BG: string = '#0E1116';
const CONFIG_FG: string = '#A6AEBA';

@Entry
@Component
struct NodeDetailPage {
  @StorageProp('appLanguage') private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private nodeId: string = '';
  @State private node: ProxyNode = EMPTY_NODE;
  @State private sections: Array<NodeDetailSection> = [];
  @State private revealed: Array<string> = [];
  @State private settings: AppSettings = DEFAULT_APP_SETTINGS;
  @State private subscriptionGroups: Array<SubscriptionGroup> = [];
  @State private lastError: string = '';
  @State private qrImage: image.PixelMap | undefined = undefined;
  @State private showFullConfig: boolean = false;
  @State private fullConfigModel: NodeFullConfigModel | null = null;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as NodeDetailParams;
    this.nodeId = params?.nodeId ?? '';
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('node.detail.title'),
        showBack: true
      })

      Scroll() {
        Column() {
          this.Hero()
          this.ActionGrid()

          if (this.qrImage !== undefined) {
            this.QrCard()
          }
          if (this.showFullConfig && this.fullConfigModel !== null) {
            this.ConfigCard()
          }

          // 字段分组：基本信息 / 传输 / 安全
          ForEach(this.sections, (section: NodeDetailSection, sIndex: number) => {
            Column() {
              this.GroupTitle(this.t(section.titleKey))
              Column() {
                ForEach(section.fields, (field: NodeDetailField, fIndex: number) => {
                  this.FieldRow(section, sIndex, field, fIndex)
                }, (field: NodeDetailField, fIndex: number) =>
                  `${sIndex}-${fIndex}-${field.labelKey}-${this.isRevealed(sIndex, fIndex) ? '1' : '0'}`)
              }
              .width('100%')
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .clip(true)
              .border({ width: 0.5, color: AppColor.border })
              .margin({ bottom: Space.lg })
            }
            .width('100%')
          }, (section: NodeDetailSection, sIndex: number) =>
            `${sIndex}-${section.titleKey}-${section.fields.length}`)

          // 状态：最近测速 + 来源
          this.StatusCard()

          if (this.lastError.length > 0) {
            Text(this.lastError)
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.danger)
              .margin({ bottom: Space.lg })
          }
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.xxl })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  // ===== Hero：头像 + 名称 + 协议/安全徽标 + 延迟/地址双 tile =====
  @Builder
  private Hero() {
    Column() {
      Row({ space: Space.sm }) {
        Text(this.node.name.length > 0 ? this.node.name : this.t('node.detail.title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        Text(this.node.protocol.toUpperCase())
          .fontSize(FontSz.caption)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.brand)
          .flexShrink(0)
        if (this.heroSecurity().length > 0) {
          Text(this.heroSecurity())
            .fontSize(FontSz.caption)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.textSecondary)
            .flexShrink(0)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: Space.sm + 2 }) {
        // 延迟 tile
        Column({ space: 3 }) {
          Text(this.t('node.field.delay'))
            .fontSize(FontSz.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textTertiary)
            .width('100%')
          Row({ space: Space.xs }) {
            Text(this.delayNumber())
              .fontFamily('monospace')
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.delayColor())
            if (this.delayUnit().length > 0) {
              Text(this.delayUnit())
                .fontSize(FontSz.footnote)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.delayColor())
            }
            Row({ space: 2 }) {
              Column().width(3).height(6).borderRadius(1).backgroundColor(this.delayColor())
              Column().width(3).height(9).borderRadius(1).backgroundColor(this.delayColor())
              Column().width(3).height(12).borderRadius(1).backgroundColor(this.delayColor())
            }
            .alignItems(VerticalAlign.Bottom)
            .margin({ left: 2 })
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(AppColor.surface)
        .borderRadius(Radius.md)
        .border({ width: 0.5, color: AppColor.border })

        // 地址 tile
        Column({ space: 5 }) {
          Text(this.t('node.field.address'))
            .fontSize(FontSz.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textTertiary)
            .width('100%')
          Text(this.heroAddress().length > 0 ? this.heroAddress() : '—')
            .fontFamily('monospace')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(AppColor.surface)
        .borderRadius(Radius.md)
        .border({ width: 0.5, color: AppColor.border })
      }
      .width('100%')
      .margin({ top: Space.lg })
    }
    .width('100%')
    .padding(18)
    .borderRadius(Radius.xl)
    .border({ width: 0.5, color: AppColor.border })
    .linearGradient({
      angle: 155,
      colors: [[AppColor.surface, 0.0], [AppColor.brandTint, 1.0]]
    })
    .margin({ top: Space.md, bottom: Space.lg })
  }

  // ===== 四宫格主操作 =====
  @Builder
  private ActionGrid() {
    Row({ space: Space.sm }) {
      this.ActionTile('copy')
      this.ActionTile('qr')
      this.ActionTile('config')
      this.ActionTile('edit')
    }
    .width('100%')
    .padding({ bottom: 18 })
  }

  @Builder
  private ActionTile(kind: string) {
    Column({ space: 6 }) {
      Image(this.actionIcon(kind))
        .width(21)
        .height(21)
        .fillColor(this.isActionActive(kind) ? AppColor.onBrand : AppColor.brand)
      Text(this.actionLabel(kind))
        .fontSize(FontSz.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isActionActive(kind) ? AppColor.onBrand : AppColor.textPrimary)
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(this.isActionActive(kind) ? AppColor.brand : AppColor.surface)
    .border({ width: 1, color: this.isActionActive(kind) ? AppColor.brand : AppColor.border })
    .opacity(this.isActionDisabled(kind) ? 0.4 : 1)
    .enabled(!this.isActionDisabled(kind))
    .onClick(() => {
      this.onActionTap(kind);
    })
  }

  // ===== 二维码展开 =====
  @Builder
  private QrCard() {
    Column({ space: Space.md }) {
      Image(this.qrImage)
        .width(188)
        .height(188)
        .objectFit(ImageFit.Contain)
        .backgroundColor(Color.White)
        .borderRadius(14)
      Text(this.t('node.detail.qr.hint'))
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textTertiary)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .border({ width: 0.5, color: AppColor.border })
    .clip(true)
    .margin({ bottom: Space.lg })
    .alignItems(HorizontalAlign.Center)
  }

  // ===== 完整配置展开（深色代码块）=====
  @Builder
  private ConfigCard() {
    Column() {
      Text(this.configText())
        .fontFamily('monospace')
        .fontSize(11)
        .fontColor(CONFIG_FG)
        .textAlign(TextAlign.Start)
        .width('100%')
    }
    .width('100%')
    .padding({ left: Space.lg, right: Space.lg, top: 14, bottom: 14 })
    .backgroundColor(CONFIG_BG)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ bottom: Space.lg })
  }

  // ===== 字段行 =====
  @Builder
  private FieldRow(section: NodeDetailSection, sIndex: number, field: NodeDetailField, fIndex: number) {
    Column() {
      Row({ space: 10 }) {
        Text(this.t(field.labelKey))
          .fontSize(FontSz.body)
          .fontColor(AppColor.textSecondary)
        Text(this.fieldDisplay(field, sIndex, fIndex))
          .fontFamily('monospace')
          .fontSize(13)
          .fontColor(this.fieldValueColor(field, sIndex, fIndex))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (field.sensitive && !this.isRevealed(sIndex, fIndex)) {
          Image($r('app.media.ic_eye'))
            .width(18)
            .height(18)
            .fillColor(AppColor.brand)
        } else {
          Image($r('app.media.ic_copy'))
            .width(15)
            .height(15)
            .fillColor(AppColor.textTertiary)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 50 })
      .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.md })
      .onClick(() => {
        this.onFieldTap(field, sIndex, fIndex);
      })
      if (fIndex < section.fields.length - 1) {
        Divider()
          .strokeWidth(0.5)
          .color(AppColor.divider)
          .margin({ left: Space.lg })
      }
    }
  }

  // ===== 状态卡片 =====
  @Builder
  private StatusCard() {
    Column() {
      this.GroupTitle(this.t('node.section.status'))
      Column() {
        Row({ space: 10 }) {
          Text(this.t('node.field.lastTest'))
            .fontSize(FontSz.body)
            .fontColor(AppColor.textSecondary)
            .layoutWeight(1)
          Text(this.relativeLastTest())
            .fontSize(13)
            .fontColor(AppColor.textTertiary)
        }
        .width('100%')
        .constraintSize({ minHeight: 50 })
        .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.md })

        if (this.node.sourceUrl.length > 0) {
          Divider()
            .strokeWidth(0.5)
            .color(AppColor.divider)
            .margin({ left: Space.lg })
          Row({ space: 10 }) {
            Text(this.t('node.detail.source'))
              .fontSize(FontSz.body)
              .fontColor(AppColor.textSecondary)
            Text(this.node.sourceUrl)
              .fontSize(13)
              .fontColor(AppColor.textPrimary)
              .layoutWeight(1)
              .textAlign(TextAlign.End)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Image($r('app.media.ic_copy'))
              .width(15)
              .height(15)
              .fillColor(AppColor.textTertiary)
          }
          .width('100%')
          .constraintSize({ minHeight: 50 })
          .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.md })
          .onClick(() => {
            this.copyText(this.node.sourceUrl);
          })
        }
      }
      .width('100%')
      .backgroundColor(AppColor.surface)
      .borderRadius(Radius.lg)
      .clip(true)
      .border({ width: 0.5, color: AppColor.border })
      .margin({ bottom: Space.lg })
    }
    .width('100%')
  }

  @Builder
  private GroupTitle(title: string) {
    Text(title)
      .fontSize(FontSz.footnote)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppColor.textTertiary)
      .width('100%')
      .padding({ left: 2, right: 2, top: 2, bottom: Space.sm })
  }

  // ===== 数据/交互辅助 =====
  private actionIcon(kind: string): Resource {
    if (kind === 'copy') {
      return $r('app.media.ic_copy');
    }
    if (kind === 'qr') {
      return $r('app.media.ic_qr_code');
    }
    if (kind === 'config') {
      return $r('app.media.ic_article');
    }
    return $r('app.media.ic_edit');
  }

  private actionLabel(kind: string): string {
    if (kind === 'copy') {
      return this.t('node.detail.tabCopy');
    }
    if (kind === 'qr') {
      return this.t('node.detail.tabQr');
    }
    if (kind === 'config') {
      return this.t('node.detail.tabConfig');
    }
    return this.t('node.detail.tabEdit');
  }

  private isActionActive(kind: string): boolean {
    if (kind === 'qr') {
      return this.qrImage !== undefined;
    }
    if (kind === 'config') {
      return this.showFullConfig;
    }
    return false;
  }

  // 订阅来源节点（带 sourceUrl/rawLink）不可手动编辑：更新订阅会覆盖本地改动，故置灰编辑入口。
  private isActionDisabled(kind: string): boolean {
    if (kind !== 'edit') {
      return false;
    }
    return this.node.sourceUrl.trim().length > 0 || this.node.rawLink.trim().length > 0;
  }

  private onActionTap(kind: string): void {
    if (kind === 'copy') {
      this.copyShareLink();
      return;
    }
    if (kind === 'qr') {
      this.toggleQr();
      return;
    }
    if (kind === 'config') {
      this.toggleFullConfig();
      return;
    }
    this.editNode();
  }

  private fieldDisplay(field: NodeDetailField, sIndex: number, fIndex: number): string {
    if (field.sensitive && !this.isRevealed(sIndex, fIndex)) {
      return MASK_TEXT;
    }
    return field.value;
  }

  private fieldValueColor(field: NodeDetailField, sIndex: number, fIndex: number): ResourceColor {
    if (field.sensitive && !this.isRevealed(sIndex, fIndex)) {
      return AppColor.textTertiary;
    }
    return AppColor.textPrimary;
  }

  private isRevealed(sIndex: number, fIndex: number): boolean {
    return this.revealed.includes(`${sIndex}-${fIndex}`);
  }

  private onFieldTap(field: NodeDetailField, sIndex: number, fIndex: number): void {
    if (field.sensitive && !this.isRevealed(sIndex, fIndex)) {
      this.revealed = this.revealed.concat([`${sIndex}-${fIndex}`]);
      return;
    }
    this.copyText(field.value);
  }

  private fieldValue(labelKey: string): string {
    for (let i = 0; i < this.sections.length; i++) {
      const fields = this.sections[i].fields;
      for (let j = 0; j < fields.length; j++) {
        if (fields[j].labelKey === labelKey) {
          return fields[j].value;
        }
      }
    }
    return '';
  }

  private heroSecurity(): string {
    return this.fieldValue('node.field.security');
  }

  private heroAddress(): string {
    const address = this.fieldValue('node.field.address');
    if (address.length === 0) {
      return '';
    }
    const port = this.fieldValue('node.field.port');
    return port.length > 0 ? `${address}:${port}` : address;
  }

  private delayNumber(): string {
    if (this.node.delayMs >= 0 && this.node.delayTestAt > 0) {
      return this.node.delayMs.toString();
    }
    return '—';
  }

  private delayUnit(): string {
    return (this.node.delayMs >= 0 && this.node.delayTestAt > 0) ? 'ms' : '';
  }

  private delayColor(): ResourceColor {
    const node = this.node;
    if (node.delayStatus === 'testing') {
      return AppColor.warning;
    }
    if (node.delayMs >= 0 && node.delayTestAt > 0) {
      if (node.delayMs <= 300) {
        return AppColor.success;
      }
      if (node.delayMs <= 900) {
        return AppColor.warning;
      }
      return AppColor.danger;
    }
    if (node.delayStatus.length > 0) {
      return AppColor.danger;
    }
    return AppColor.textTertiary;
  }

  private relativeLastTest(): string {
    const at = this.node.delayTestAt;
    if (at <= 0) {
      return this.t('node.delay.pending');
    }
    const diff = Date.now() - at;
    if (diff < 60000) {
      return this.t('node.time.justNow');
    }
    const minutes = Math.floor(diff / 60000);
    if (minutes < 60) {
      return this.f1('node.time.minutesAgo', 'n', minutes.toString());
    }
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
      return this.f1('node.time.hoursAgo', 'n', hours.toString());
    }
    const days = Math.floor(hours / 24);
    return this.f1('node.time.daysAgo', 'n', days.toString());
  }

  private configText(): string {
    if (this.fullConfigModel === null) {
      return '';
    }
    return this.fullConfigModel.content.length > 0 ? this.fullConfigModel.content : this.fullConfigModel.message;
  }

  private async loadState(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const settings = await SETTINGS_CONTROLLER.load(context);
    this.settings = settings;
    this.language = settings.language;
    const state = await NODES_CONTROLLER.load(context, this.language);
    this.subscriptionGroups = state.subscriptionGroups;
    const found = this.findNode(state.subscriptionGroups, this.nodeId);
    if (found !== null) {
      this.node = found;
      this.sections = buildNodeDetailSections(found.outboundJson, found.protocol);
    }
    this.lastError = state.lastError;
  }

  private findNode(groups: Array<SubscriptionGroup>, nodeId: string): ProxyNode | null {
    for (let i = 0; i < groups.length; i++) {
      const group = groups[i];
      for (let j = 0; j < group.nodes.length; j++) {
        if (group.nodes[j].id === nodeId) {
          return group.nodes[j];
        }
      }
    }
    return null;
  }

  private copyShareLink(): void {
    const link = formatOutboundJsonToShareLink(this.node.outboundJson, this.node.name);
    if (link.length === 0) {
      this.lastError = this.t('node.detail.copyFailed');
      return;
    }
    this.copyText(link);
  }

  private toggleFullConfig(): void {
    if (this.showFullConfig) {
      this.showFullConfig = false;
      return;
    }
    this.fullConfigModel = buildNodeFullConfigModel(this.node, this.settings, this.subscriptionGroups);
    this.showFullConfig = true;
  }

  private toggleQr(): void {
    if (this.qrImage !== undefined) {
      this.qrImage = undefined;
      return;
    }
    this.generateQr();
  }

  private async generateQr(): Promise<void> {
    const link = formatOutboundJsonToShareLink(this.node.outboundJson, this.node.name);
    if (link.length === 0) {
      this.lastError = this.t('node.detail.copyFailed');
      return;
    }
    try {
      const options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        height: 400,
        width: 400
      };
      this.qrImage = await generateBarcode.createBarcode(link, options);
    } catch (error) {
      this.lastError = this.f1('error.qrGenerate', 'error', JSON.stringify(error));
    }
  }

  private editNode(): void {
    const configType: string = this.node.configType ?? 'outbound';
    // 代理链 / 策略组 → 高级出站编辑器
    if (configType === 'proxy-chain' || configType === 'policy-group') {
      this.getUIContext().getRouter().pushUrl({
        url: AppRoute.ADVANCED_OUTBOUND,
        params: {
          mode: configType,
          nodeId: this.node.id
        }
      }).catch((err: Error) => {});
      return;
    }
    // 完整配置 / 自定义 / 表单无法表达的协议 → JSON 编辑器
    if (configType === 'full' || this.node.protocol === 'custom' || !isManualEditProtocol(this.node.protocol)) {
      this.getUIContext().getRouter().pushUrl({
        url: AppRoute.JSON_IMPORT,
        params: {
          nodeId: this.node.id
        }
      }).catch((err: Error) => {});
      return;
    }
    // 标准分享链接节点 → 表单编辑器
    this.getUIContext().getRouter().pushUrl({
      url: AppRoute.NODE_EDIT,
      params: {
        nodeId: this.node.id,
        protocol: normalizeManualEditProtocol(this.node.protocol)
      }
    }).catch((err: Error) => {});
  }

  private copyText(value: string): void {
    if (value.length === 0) {
      return;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      pasteboard.getSystemPasteboard().setDataSync(pasteData);
    } catch (error) {
      // 复制失败仍给出反馈，避免静默
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: this.t('node.detail.copied') });
    } catch (err) {
      // ignore
    }
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }

  private t(key: string): string {
    return translate(this.language, key);
  }
}
