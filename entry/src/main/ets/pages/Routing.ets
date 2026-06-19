import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, ProxyNode, RoutingRule } from '../core/Profile';
import {
  exportRoutingRulesJson,
  importRoutingRulesJson,
  resetRoutingRulesFromPreset,
  ROUTING_RULE_PRESETS,
  RoutingPresetId,
  RoutingPresetInfo
} from '../core/RoutingRules';
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { ensureReadPasteboardPermission } from '../utils/ClipboardPermission';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';
import { RoutingRuleDialog } from './routing/RoutingRuleDialog';

@Entry
@Component
struct RoutingPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private trafficMode: string = 'rules';
  @State private routingStrategy: string = 'AsIs';
  @State private routeOnlyEnabled: boolean = false;
  @State private adBlockEnabled: boolean = false;
  @State private routingRules: Array<RoutingRule> = [];
  @State private showRuleDialog: boolean = false;
  @State private ruleDialogTitle: string = '';
  @State private editingRuleId: string = '';
  @State private advancedOutboundTargets: Array<string> = [];
  @State private initialRule: RoutingRule = {
    id: '',
    remarks: '',
    domain: [],
    ip: [],
    process: [],
    outboundTag: 'proxy',
    port: '',
    network: '',
    protocol: [],
    enabled: true,
    locked: false
  };
  private draft: SettingsDraft | null = null;

  aboutToAppear(): void {
    this.loadState();
  }

  onPageShow(): void {
    this.loadState();
  }

  build() {
    Stack() {
      Column() {
        PageHeader({
          title: this.t('screen.routing.title'),
          summary: this.t(`routing.mode.${this.trafficMode}`),
          showBack: true
        })

        Scroll() {
          Column({ space: Space.lg }) {

            // 流量模式
            SectionHeader({ title: this.t('routing.trafficMode') })
            Column() {
              this.TrafficModeRow('global', this.t('routing.mode.global'), '所有流量代理', $r('app.media.ic_route'))
              this.RowDivider()
              this.TrafficModeRow('rules', this.t('routing.mode.rules'), '按规则智能分流', $r('app.media.ic_settings'))
              this.RowDivider()
              this.TrafficModeRow('direct', this.t('routing.mode.direct'), '所有流量直连', $r('app.media.ic_share'))

              if (this.trafficMode === 'rules') {
                this.RowDivider()
                this.RouteOnlyRow()
              }
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })

            this.GroupFooter(this.getTrafficModeDescription())

            // 域名策略
            SectionHeader({ title: this.t('routing.domainStrategy') })
            Column() {
              this.StrategyRow('AsIs', '仅用域名 (AsIs)', '直接使用域名进行匹配分流，解析效率最高，但不匹配 IP 类规则。')
              this.RowDivider()
              this.StrategyRow('IPIfNonMatch', '未匹配时解析 (IPIfNonMatch)', '域名未命中任何规则时，解析为 IP 再次匹配。推荐配置，兼顾速度与准确性。')
              this.RowDivider()
              this.StrategyRow('IPOnDemand', '按需解析 (IPOnDemand)', '在规则匹配到 IP 规则时才发起 DNS 解析，适用于较严格的分流场景。')
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })

            // 预置规则集
            SectionHeader({ title: '预置规则集' })
            Column() {
              this.PresetRow(
                this.t('routing.global.title'),
                this.t('routing.global.detail'),
                $r('app.media.ic_route'),
                '• 匹配规则：所有入站请求均被路由到代理出站(proxy)\n• 场景应用：不需要区分内外网，完全通过代理节点访问网络'
              )
              this.RowDivider()
              this.PresetRow(
                this.t('routing.bypassLanCn.title'),
                this.t('routing.bypassLanCn.detail'),
                $r('app.media.ic_link'),
                '• 匹配规则：\n  - 局域网私有IP (geoip:private) -> 直连(direct)\n  - 境内IP网段 (geoip:cn) -> 直连(direct)\n  - 境内常见域名 (geosite:cn) -> 直连(direct)\n• 其它未匹配流量自动通过代理出站'
              )
              this.RowDivider()
              this.AdBlockRow()
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })

            SectionHeader({ title: this.t('routing.customRulesets.title') })
            Column() {
              this.CustomRulesHeader()
              if (this.routingRules.length === 0) {
                this.RowDivider()
                this.EmptyCustomRulesRow()
              } else {
                ForEach(this.routingRules, (rule: RoutingRule, index: number) => {
                  this.RowDivider()
                  this.CustomRuleRow(rule, index)
                }, (rule: RoutingRule) => rule.id)
              }
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })

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

      if (this.showRuleDialog) {
        RoutingRuleDialog({
          language: this.language,
          title: this.ruleDialogTitle,
          initialRule: this.initialRule,
          advancedOutboundTargets: this.advancedOutboundTargets,
          onCancel: () => {
            this.showRuleDialog = false;
          },
          onConfirm: (rule: RoutingRule) => {
            this.saveRule(rule);
          }
        })
      }
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(AppColor.divider)
      .margin({ left: Space.lg })
  }

  @Builder
  private GroupFooter(text: string) {
    Text(text)
      .fontSize(FontSz.footnote)
      .fontColor(AppColor.textTertiary)
      .lineHeight(16)
      .width('100%')
      .padding({ left: Space.lg + Space.xs, right: Space.lg + Space.xs, top: Space.xs })
  }

  @Builder
  private TrafficModeRow(value: string, title: string, subtitle: string, icon: Resource) {
    Row({ space: Space.md }) {
      Column() {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor(this.trafficMode === value ? AppColor.brand : AppColor.textTertiary)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.trafficMode === value ? AppColor.brandTint : AppColor.surfaceAlt)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(subtitle)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.trafficMode === value) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(AppColor.brand)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      this.trafficMode = value;
      this.persistSettings(this.f1('log.routingStrategy', 'value', title));
    })
  }

  @Builder
  private RouteOnlyRow() {
    Row({ space: Space.md }) {
      Column({ space: 3 }) {
        Text(this.t('settings.routeOnly'))
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text('局域网和中国境内流量将直接连接。')
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.routeOnlyEnabled })
        .selectedColor(AppColor.brand)
        .switchPointColor(AppColor.onBrand)
        .onChange((isOn: boolean) => {
          this.routeOnlyEnabled = isOn;
          this.persistSettings(this.t('settings.routeOnly') + ': ' + (isOn ? this.t('action.on') : this.t('action.off')));
        })
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private AdBlockRow() {
    Row({ space: Space.md }) {
      Column() {
        Image($r('app.media.ic_delete'))
          .width(20)
          .height(20)
          .fillColor(this.adBlockEnabled ? AppColor.brand : AppColor.textTertiary)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.adBlockEnabled ? AppColor.brandTint : AppColor.surfaceAlt)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Text(this.t('routing.blockAds.title'))
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(this.t('routing.blockAds.detail'))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.adBlockEnabled })
        .selectedColor(AppColor.brand)
        .switchPointColor(AppColor.onBrand)
        .onChange((isOn: boolean) => {
          this.adBlockEnabled = isOn;
          this.persistSettings(this.t('routing.blockAds.title') + ': ' + (isOn ? this.t('action.on') : this.t('action.off')));
        })
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private StrategyRow(value: string, title: string, description: string) {
    Row({ space: Space.md }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.routingStrategy === value ? AppColor.brand : AppColor.textPrimary)
        Text(description)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .lineHeight(16)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.routingStrategy === value) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(AppColor.brand)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      this.routingStrategy = value;
      this.persistSettings(this.f1('log.routingStrategy', 'value', value));
    })
  }

  @Builder
  private PresetRow(title: string, detail: string, icon: Resource, rulesInfo: string) {
    Row({ space: Space.md }) {
      Column() {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor(AppColor.brand)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.brandTint)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(detail)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor(AppColor.textTertiary)
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      this.showPresetDetails(title, detail, rulesInfo);
    })
  }

  @Builder
  private CustomRulesHeader() {
    Row({ space: Space.md }) {
      Column() {
        Image($r('app.media.ic_settings'))
          .width(20)
          .height(20)
          .fillColor(AppColor.brand)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.brandTint)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Text(this.t('routing.customRulesets.title'))
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(this.customRuleSummary())
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: Space.xs }) {
        this.RuleHeaderActionButton($r('app.media.ic_cloud_download'), 'preset')
        this.RuleHeaderActionButton($r('app.media.ic_article'), 'import')
        this.RuleHeaderActionButton($r('app.media.ic_qr_code'), 'qrImport')
        this.RuleHeaderActionButton($r('app.media.ic_share'), 'export')
        this.RuleHeaderActionButton($r('app.media.ic_add'), 'add')
      }
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private RuleHeaderActionButton(icon: Resource, action: string) {
    Button() {
      Image(icon)
        .width(17)
        .height(17)
        .fillColor(action === 'add' ? AppColor.onBrand : AppColor.textSecondary)
    }
    .width(34)
    .height(34)
    .backgroundColor(action === 'add' ? AppColor.brand : AppColor.surfaceAlt)
    .borderRadius(17)
    .onClick(() => {
      this.handleRuleHeaderAction(action);
    })
  }

  @Builder
  private EmptyCustomRulesRow() {
    Row({ space: Space.md }) {
      Text(this.t('routing.rule.empty'))
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textTertiary)
        .layoutWeight(1)
        .lineHeight(16)
      Button(this.t('routing.rule.add'))
        .height(34)
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.onBrand)
        .backgroundColor(AppColor.brand)
        .borderRadius(Radius.pill)
        .onClick(() => {
          this.openAddRule();
        })
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private CustomRuleRow(rule: RoutingRule, index: number) {
    Row({ space: Space.md }) {
      Column() {
        Image(this.ruleIcon(rule))
          .width(18)
          .height(18)
          .fillColor(rule.enabled ? this.ruleAccentColor(rule) : AppColor.textTertiary)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(rule.enabled ? this.ruleAccentTint(rule) : AppColor.surfaceAlt)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 4 }) {
        Row({ space: Space.sm }) {
          Text(rule.remarks)
            .fontSize(FontSz.callout)
            .fontWeight(FontWeight.Medium)
            .fontColor(rule.enabled ? AppColor.textPrimary : AppColor.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(rule.outboundTag)
            .fontSize(FontSz.caption)
            .fontColor(this.ruleAccentColor(rule))
            .padding({ left: Space.sm, right: Space.sm, top: 2, bottom: 2 })
            .backgroundColor(this.ruleAccentTint(rule))
            .borderRadius(Radius.sm)
          if (rule.locked) {
            Text(this.t('routing.rule.locked.short'))
              .fontSize(FontSz.caption)
              .fontColor(AppColor.warning)
              .padding({ left: Space.sm, right: Space.sm, top: 2, bottom: 2 })
              .backgroundColor(AppColor.surfaceAlt)
              .borderRadius(Radius.sm)
          }
        }
        .width('100%')

        Text(this.describeRule(rule))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(2)
          .lineHeight(16)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        this.openEditRule(rule);
      })

      Column({ space: Space.xs }) {
        Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
          .selectedColor(AppColor.brand)
          .switchPointColor(AppColor.onBrand)
          .onChange((isOn: boolean) => {
            this.toggleRule(rule.id, isOn);
          })

        Row({ space: Space.xs }) {
          this.RuleIconButton($r('app.media.ic_arrow_downward'), index > 0, true, 'up', index, rule.id)
          this.RuleIconButton($r('app.media.ic_arrow_downward'), index < this.routingRules.length - 1, false, 'down', index, rule.id)
          this.RuleIconButton($r('app.media.ic_edit'), true, false, 'edit', index, rule.id)
          this.RuleIconButton($r('app.media.ic_delete'), true, false, 'delete', index, rule.id)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private RuleIconButton(icon: Resource, enabled: boolean, rotateUp: boolean, action: string, index: number, ruleId: string) {
    Button() {
      Image(icon)
        .width(14)
        .height(14)
        .fillColor(AppColor.textSecondary)
        .rotate({ angle: rotateUp ? 180 : 0 })
    }
    .width(28)
    .height(28)
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.35)
    .backgroundColor(AppColor.surfaceAlt)
    .borderRadius(14)
    .onClick(() => {
      this.handleRuleIconAction(action, index, ruleId);
    })
  }

  private getTrafficModeDescription(): string {
    if (this.trafficMode === 'global') {
      return '全局代理模式下，未命中广告拦截或自定义规则的流量都会导向代理节点。';
    } else if (this.trafficMode === 'rules') {
      return '规则分流模式下，客户端会解析域名和 IP，并对照路由规则集，符合绕过条件的直连，其余流量通过代理出站。';
    } else {
      return '全局直连模式下，所有网络流量均绕过代理服务器直接出站。此时代理服务不会对您的流量进行中转。';
    }
  }

  private showPresetDetails(title: string, detail: string, rules: string): void {
    AlertDialog.show({
      title: title,
      message: detail + "\n\n【核心规则配置】\n" + rules,
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: this.t('action.use') + ' / ' + '启用预设',
        fontColor: AppColor.onBrand,
        backgroundColor: AppColor.brand,
        action: () => {
          SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.presetOpened', 'title', title));
        }
      },
      secondaryButton: {
        value: '关闭',
        fontColor: AppColor.textSecondary,
        backgroundColor: AppColor.bg,
        action: () => {}
      }
    })
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    const settings = await SETTINGS_CONTROLLER.load(context);
    this.draft = SETTINGS_CONTROLLER.toDraft(settings);
    this.language = this.draft.language;
    this.trafficMode = this.draft.trafficMode;
    this.routingStrategy = this.draft.routingDomainStrategy;
    this.routeOnlyEnabled = this.draft.routeOnlyEnabled;
    this.adBlockEnabled = this.draft.adBlockEnabled;
    this.routingRules = this.copyRules(this.draft.routingRules);
    const profile = await SubscriptionStore.load(context);
    this.advancedOutboundTargets = this.resolveAdvancedOutboundTargets(profile.nodes, profile.selectedNodeId);
  }

  private async persistSettings(logMessage: string): Promise<void> {
    if (this.draft === null) {
      return;
    }
    this.draft.trafficMode = this.trafficMode;
    this.draft.routingDomainStrategy = this.routingStrategy;
    this.draft.routeOnlyEnabled = this.routeOnlyEnabled;
    this.draft.adBlockEnabled = this.adBlockEnabled;
    this.draft.routingRules = this.copyRules(this.routingRules);
    const context = getContext(this) as common.Context;
    const saved = await SETTINGS_CONTROLLER.save(context, this.draft);
    this.draft = SETTINGS_CONTROLLER.toDraft(saved);
    this.language = this.draft.language;
    this.routingRules = this.copyRules(this.draft.routingRules);
    SHARED_RUNTIME_CONTROLLER.appendLog(logMessage);
  }

  private openAddRule(): void {
    this.editingRuleId = '';
    this.initialRule = this.createBlankRule();
    this.ruleDialogTitle = this.t('routing.rule.add');
    this.showRuleDialog = true;
  }

  private openEditRule(rule: RoutingRule): void {
    this.editingRuleId = rule.id;
    this.initialRule = this.copyRule(rule);
    this.ruleDialogTitle = this.t('routing.rule.edit');
    this.showRuleDialog = true;
  }

  private handleRuleHeaderAction(action: string): void {
    if (action === 'preset') {
      this.openPresetPicker();
    } else if (action === 'import') {
      this.confirmClipboardImport();
    } else if (action === 'qrImport') {
      this.scanRulesFromQr();
    } else if (action === 'export') {
      this.exportRulesToClipboard();
    } else if (action === 'add') {
      this.openAddRule();
    }
  }

  private openPresetPicker(): void {
    const labels = new Array<string>();
    for (let index = 0; index < ROUTING_RULE_PRESETS.length; index++) {
      labels.push(this.t(ROUTING_RULE_PRESETS[index].titleKey));
    }
    TextPickerDialog.show({
      range: labels,
      selected: 0,
      onAccept: (value: TextPickerResult) => {
        const index = this.pickerIndex(value);
        if (index >= 0 && index < ROUTING_RULE_PRESETS.length) {
          this.confirmPresetImport(ROUTING_RULE_PRESETS[index]);
        }
      }
    })
  }

  private confirmClipboardImport(): void {
    AlertDialog.show({
      title: this.t('action.import'),
      message: this.t('routing.preset.importConfirm'),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: this.t('action.import'),
        fontColor: AppColor.onBrand,
        backgroundColor: AppColor.brand,
        action: () => {
          this.importRulesFromClipboard();
        }
      },
      secondaryButton: {
        value: this.t('action.cancel'),
        fontColor: AppColor.textSecondary,
        backgroundColor: AppColor.bg,
        action: () => {}
      }
    })
  }

  private confirmPresetImport(preset: RoutingPresetInfo): void {
    AlertDialog.show({
      title: this.t(preset.titleKey),
      message: this.t('routing.preset.importConfirm') + '\n\n' + this.t(preset.detailKey),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: this.t('action.import'),
        fontColor: AppColor.onBrand,
        backgroundColor: AppColor.brand,
        action: () => {
          this.applyPresetImport(preset.id, this.t(preset.titleKey));
        }
      },
      secondaryButton: {
        value: this.t('action.cancel'),
        fontColor: AppColor.textSecondary,
        backgroundColor: AppColor.bg,
        action: () => {}
      }
    })
  }

  private async applyPresetImport(presetId: RoutingPresetId, presetName: string): Promise<void> {
    this.routingRules = resetRoutingRulesFromPreset(this.routingRules, presetId);
    await this.persistSettings(this.f1('log.routingPresetImported', 'name', presetName));
    promptAction.showToast({ message: this.f1('log.routingPresetImported', 'name', presetName) });
  }

  private async importRulesFromClipboard(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      if (!await ensureReadPasteboardPermission(context)) {
        promptAction.showToast({ message: this.t('prompt.clipboardEmpty') });
        return;
      }
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (!systemPasteboard.hasDataSync()) {
        promptAction.showToast({ message: this.t('prompt.clipboardEmpty') });
        return;
      }
      const pasteData = await systemPasteboard.getData();
      const text = pasteData.getPrimaryText();
      if (!text || text.trim().length === 0) {
        promptAction.showToast({ message: this.t('prompt.clipboardEmpty') });
        return;
      }

      await this.importRulesFromText(text, 'log.routingRulesImported');
    } catch (error) {
      promptAction.showToast({ message: this.t('routing.rule.importFailed') });
      SHARED_RUNTIME_CONTROLLER.appendLog(JSON.stringify(error));
    }
  }

  private async scanRulesFromQr(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(context, options);
      if (!result || !result.originalValue || result.originalValue.trim().length === 0) {
        return;
      }
      this.confirmQrImport(result.originalValue.trim());
    } catch (error) {
      const errorRecord = error as Record<string, Object>;
      const code = errorRecord['code'];
      if (code === 20001 || code === '20001') {
        return;
      }
      const message = this.f1('routing.rule.scanFailed', 'error', JSON.stringify(error));
      promptAction.showToast({ message });
      SHARED_RUNTIME_CONTROLLER.appendLog(message);
    }
  }

  private confirmQrImport(content: string): void {
    AlertDialog.show({
      title: this.t('routing.rule.importFromQr'),
      message: this.t('routing.preset.importConfirm'),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: this.t('action.import'),
        fontColor: AppColor.onBrand,
        backgroundColor: AppColor.brand,
        action: () => {
          this.importRulesFromText(content, 'log.routingRulesImportedFromQr');
        }
      },
      secondaryButton: {
        value: this.t('action.cancel'),
        fontColor: AppColor.textSecondary,
        backgroundColor: AppColor.bg,
        action: () => {}
      }
    })
  }

  private async importRulesFromText(content: string, logKey: string): Promise<void> {
    const result = importRoutingRulesJson(this.routingRules, content);
    if (!result.success) {
      promptAction.showToast({ message: this.t('routing.rule.importFailed') });
      return;
    }

    this.routingRules = result.rules;
    const message = this.f1(logKey, 'count', result.count.toString());
    await this.persistSettings(message);
    promptAction.showToast({ message });
  }

  private async exportRulesToClipboard(): Promise<void> {
    if (this.routingRules.length === 0) {
      promptAction.showToast({ message: this.t('routing.rule.exportEmpty') });
      return;
    }
    const systemPasteboard = pasteboard.getSystemPasteboard();
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, exportRoutingRulesJson(this.routingRules));
    await systemPasteboard.setData(pasteData);
    const message = this.f1('log.routingRulesExported', 'count', this.routingRules.length.toString());
    SHARED_RUNTIME_CONTROLLER.appendLog(message);
    promptAction.showToast({ message });
  }

  private pickerIndex(value: TextPickerResult): number {
    if (value.index !== undefined) {
      if (typeof value.index === 'number') {
        return value.index;
      }
      if (typeof value.index === 'string') {
        return Number(value.index);
      }
      if (Array.isArray(value.index)) {
        return Number(value.index[0]);
      }
    }
    return 0;
  }

  private handleRuleIconAction(action: string, index: number, ruleId: string): void {
    if (action === 'up') {
      this.moveRule(index, -1);
    } else if (action === 'down') {
      this.moveRule(index, 1);
    } else if (action === 'delete') {
      this.deleteRule(ruleId);
    } else if (action === 'edit') {
      const rule = this.findRule(ruleId);
      if (rule !== undefined) {
        this.openEditRule(rule);
      }
    }
  }

  private async saveRule(rule: RoutingRule): Promise<void> {
    const next = this.copyRules(this.routingRules);
    if (this.editingRuleId.length === 0) {
      const created = this.copyRule(rule);
      created.id = this.createRuleId();
      next.push(created);
    } else {
      for (let index = 0; index < next.length; index++) {
        if (next[index].id === this.editingRuleId) {
          const updated = this.copyRule(rule);
          updated.id = this.editingRuleId;
          next[index] = updated;
          break;
        }
      }
    }
    this.routingRules = next;
    this.showRuleDialog = false;
    await this.persistSettings(this.f1('log.routingRuleSaved', 'name', rule.remarks));
  }

  private async toggleRule(ruleId: string, enabled: boolean): Promise<void> {
    const next = this.copyRules(this.routingRules);
    for (let index = 0; index < next.length; index++) {
      if (next[index].id === ruleId) {
        next[index].enabled = enabled;
        this.routingRules = next;
        await this.persistSettings(this.f1('log.routingRuleSaved', 'name', next[index].remarks));
        return;
      }
    }
  }

  private async deleteRule(ruleId: string): Promise<void> {
    const next = new Array<RoutingRule>();
    let removedName = '';
    for (let index = 0; index < this.routingRules.length; index++) {
      const rule = this.routingRules[index];
      if (rule.id === ruleId) {
        removedName = rule.remarks;
      } else {
        next.push(this.copyRule(rule));
      }
    }
    this.routingRules = next;
    await this.persistSettings(this.f1('log.routingRuleDeleted', 'name', removedName));
  }

  private async moveRule(index: number, delta: number): Promise<void> {
    const target = index + delta;
    if (target < 0 || target >= this.routingRules.length) {
      return;
    }
    const next = this.copyRules(this.routingRules);
    const current = next[index];
    next[index] = next[target];
    next[target] = current;
    this.routingRules = next;
    await this.persistSettings(this.t('log.routingRuleReordered'));
  }

  private customRuleSummary(): string {
    if (this.routingRules.length === 0) {
      return this.t('routing.rule.empty.short');
    }
    let enabledCount = 0;
    for (let index = 0; index < this.routingRules.length; index++) {
      if (this.routingRules[index].enabled) {
        enabledCount++;
      }
    }
    return this.t('routing.customRulesets.detail') + ` · ${enabledCount}/${this.routingRules.length}`;
  }

  private describeRule(rule: RoutingRule): string {
    const parts = new Array<string>();
    this.addDescriptionPart(parts, 'domain', rule.domain);
    this.addDescriptionPart(parts, 'ip', rule.ip);
    this.addDescriptionPart(parts, 'process', rule.process);
    if (rule.port.length > 0) {
      parts.push(`port=${rule.port}`);
    }
    this.addDescriptionPart(parts, 'protocol', rule.protocol);
    if (rule.network.length > 0) {
      parts.push(`network=${rule.network}`);
    }
    if (parts.length === 0) {
      return this.t('routing.rule.noMatcher');
    }
    return parts.join(' / ');
  }

  private addDescriptionPart(parts: Array<string>, label: string, values: Array<string>): void {
    if (values.length > 0) {
      parts.push(`${label}=${values.join(',')}`);
    }
  }

  private ruleIcon(rule: RoutingRule): Resource {
    if (rule.outboundTag === 'block') {
      return $r('app.media.ic_delete');
    }
    return $r('app.media.ic_route');
  }

  private ruleAccentColor(rule: RoutingRule): Resource {
    if (rule.outboundTag === 'direct') {
      return AppColor.success;
    }
    if (rule.outboundTag === 'block') {
      return AppColor.danger;
    }
    return AppColor.brand;
  }

  private ruleAccentTint(rule: RoutingRule): Resource {
    if (rule.outboundTag === 'direct') {
      return AppColor.successTint;
    }
    if (rule.outboundTag === 'block') {
      return AppColor.dangerTint;
    }
    return AppColor.brandTint;
  }

  private resolveAdvancedOutboundTargets(nodes: Array<ProxyNode>, selectedNodeId: string): Array<string> {
    for (let index = 0; index < nodes.length; index++) {
      if (nodes[index].id === selectedNodeId) {
        const target = this.advancedTargetOf(nodes[index]);
        return target.length > 0 ? [target] : [];
      }
    }
    return [];
  }

  private advancedTargetOf(node: ProxyNode): string {
    if (node.configType === 'proxy-chain' || node.protocol === 'proxy-chain') {
      return 'proxy-chain';
    }
    if (node.configType === 'policy-group' || node.protocol === 'policy-group') {
      return 'policy-group';
    }
    return '';
  }

  private createBlankRule(): RoutingRule {
    return {
      id: '',
      remarks: '',
      domain: [],
      ip: [],
      process: [],
      outboundTag: 'proxy',
      port: '',
      network: '',
      protocol: [],
      enabled: true,
      locked: false
    };
  }

  private createRuleId(): string {
    return `routing-rule-${Date.now()}`;
  }

  private findRule(ruleId: string): RoutingRule | undefined {
    for (let index = 0; index < this.routingRules.length; index++) {
      if (this.routingRules[index].id === ruleId) {
        return this.routingRules[index];
      }
    }
    return undefined;
  }

  private copyRules(rules: Array<RoutingRule>): Array<RoutingRule> {
    const result = new Array<RoutingRule>();
    for (let index = 0; index < rules.length; index++) {
      result.push(this.copyRule(rules[index]));
    }
    return result;
  }

  private copyRule(rule: RoutingRule): RoutingRule {
    return {
      id: rule.id,
      remarks: rule.remarks,
      domain: rule.domain.slice(),
      ip: rule.ip.slice(),
      process: rule.process.slice(),
      outboundTag: rule.outboundTag,
      port: rule.port,
      network: rule.network,
      protocol: rule.protocol.slice(),
      enabled: rule.enabled,
      locked: rule.locked
    };
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
