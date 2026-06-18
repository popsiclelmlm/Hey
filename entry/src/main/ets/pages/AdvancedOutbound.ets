import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { buildPolicyGroupConfigFromNodes, buildProxyChainConfigFromNodes, isAdvancedOutboundBuildableNode, PolicyGroupStrategy } from '../core/AdvancedOutboundBuilder';
import { AppLanguage, ProxyNode, SubscriptionProfile } from '../core/Profile';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { formatOne, formatTwo, localizeCoreMessage } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

interface AdvancedOutboundCandidate {
  key: string;
  groupName: string;
  node: ProxyNode;
}

@Entry
@Component
struct AdvancedOutboundPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private mode: string = 'proxy-chain';
  @State private nodeName: string = '';
  @State private strategy: PolicyGroupStrategy = 'roundRobin';
  @State private candidates: Array<AdvancedOutboundCandidate> = [];
  @State private selectedNodeKeys: Array<string> = [];
  @State private lastError: string = '';
  @State private isBusy: boolean = false;
  private strategyOptions: Array<string> = ['roundRobin', 'random', 'leastPing', 'leastLoad'];

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    this.mode = (params?.mode as string) === 'policy-group' ? 'policy-group' : 'proxy-chain';
    this.loadState();
  }

  onPageShow(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.pageTitle(),
        summary: this.f2('advancedOutbound.selectedSummary', 'count', `${this.selectedNodeKeys.length}`, 'min', `${this.requiredMemberCount()}`),
        showBack: true
      })

      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: Space.lg }) {
            SectionHeader({ title: this.t('advancedOutbound.basic') })
            Column({ space: Space.lg }) {
              this.NameInput()

              if (this.mode === 'policy-group') {
                this.StrategySelector()
              }
            }
            .width('100%')
            .padding(Space.lg)
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .margin({ left: Space.lg, right: Space.lg })

            this.SelectedMembersSection()

            SectionHeader({ title: this.t('advancedOutbound.availableMembers') })
            if (this.candidates.length === 0) {
              this.EmptyState()
            } else {
              Column() {
                ForEach(this.candidates, (candidate: AdvancedOutboundCandidate) => {
                  this.CandidateRow(candidate)
                  if (this.candidateIndex(candidate.key) < this.candidates.length - 1) {
                    this.RowDivider()
                  }
                }, (candidate: AdvancedOutboundCandidate) => candidate.key)
              }
              .width('100%')
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .clip(true)
              .margin({ left: Space.lg, right: Space.lg })
            }

            if (this.lastError.length > 0) {
              Text(this.lastError)
                .fontSize(FontSz.footnote)
                .fontColor(AppColor.danger)
                .width('100%')
                .lineHeight(16)
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
              Text(this.t('advancedOutbound.save'))
                .fontSize(FontSz.headline)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.canSave() ? AppColor.onBrand : AppColor.textTertiary)
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(Radius.pill)
          .enabled(this.canSave())
          .backgroundColor(this.canSave() ? AppColor.brand : AppColor.surfaceAlt)
          .onClick(() => {
            this.saveAdvancedOutbound();
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
  private NameInput() {
    Column({ space: Space.sm }) {
      Text(this.t('advancedOutbound.name'))
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textSecondary)
        .width('100%')
      TextInput({
        placeholder: this.mode === 'policy-group' ? this.t('advancedOutbound.defaultPolicyGroupName') : this.t('advancedOutbound.defaultProxyChainName'),
        text: this.nodeName
      })
        .height(44)
        .fontSize(FontSz.body)
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .backgroundColor(AppColor.surfaceAlt)
        .borderRadius(Radius.md)
        .padding({ left: Space.md, right: Space.md })
        .onChange((value: string) => {
          this.nodeName = value;
        })
    }
    .width('100%')
  }

  @Builder
  private StrategySelector() {
    Column({ space: Space.sm }) {
      Text(this.t('advancedOutbound.strategy'))
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textSecondary)
        .width('100%')
      Row({ space: Space.xs }) {
        ForEach(this.strategyOptions, (option: string) => {
          Text(this.strategyLabel(option))
            .layoutWeight(1)
            .height(34)
            .fontSize(FontSz.caption)
            .fontWeight(this.strategy === option ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.strategy === option ? AppColor.onBrand : AppColor.textSecondary)
            .backgroundColor(this.strategy === option ? AppColor.brand : Color.Transparent)
            .textAlign(TextAlign.Center)
            .borderRadius(Radius.sm)
            .onClick(() => {
              this.strategy = option as PolicyGroupStrategy;
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

  @Builder
  private SelectedMembersSection() {
    if (this.selectedNodeKeys.length > 0) {
      SectionHeader({ title: this.t('advancedOutbound.selectedMembers') })
      Column() {
        ForEach(this.selectedCandidates(), (candidate: AdvancedOutboundCandidate, index: number) => {
          this.SelectedMemberRow(candidate, index)
          if (index < this.selectedNodeKeys.length - 1) {
            this.RowDivider()
          }
        }, (candidate: AdvancedOutboundCandidate) => candidate.key)
      }
      .width('100%')
      .backgroundColor(AppColor.surface)
      .borderRadius(Radius.lg)
      .clip(true)
      .margin({ left: Space.lg, right: Space.lg })
    }
  }

  @Builder
  private SelectedMemberRow(candidate: AdvancedOutboundCandidate, index: number) {
    Row({ space: Space.md }) {
      Text(`${index + 1}`)
        .fontSize(FontSz.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.onBrand)
        .textAlign(TextAlign.Center)
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor(AppColor.brand)

      Column({ space: 3 }) {
        Text(candidate.node.name)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.candidateSubtitle(candidate))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: Space.xs }) {
        this.MemberIconButton($r('app.media.ic_arrow_downward'), index > 0, true, 'up', candidate.key)
        this.MemberIconButton($r('app.media.ic_arrow_downward'), index < this.selectedNodeKeys.length - 1, false, 'down', candidate.key)
        this.MemberIconButton($r('app.media.ic_delete'), true, false, 'remove', candidate.key)
      }
    }
    .width('100%')
    .padding(Space.lg)
  }

  @Builder
  private CandidateRow(candidate: AdvancedOutboundCandidate) {
    Row({ space: Space.md }) {
      if (this.selectedOrder(candidate.key) > 0) {
        Text(`${this.selectedOrder(candidate.key)}`)
          .fontSize(FontSz.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.onBrand)
          .textAlign(TextAlign.Center)
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor(AppColor.brand)
      } else {
        Column()
          .width(28)
          .height(28)
          .borderRadius(14)
          .border({ width: 1, color: AppColor.border })
      }

      Column({ space: 3 }) {
        Text(candidate.node.name)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.candidateSubtitle(candidate))
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isCandidateSelected(candidate.key)) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(AppColor.brand)
      } else {
        Image($r('app.media.ic_add'))
          .width(20)
          .height(20)
          .fillColor(AppColor.textTertiary)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      this.toggleCandidate(candidate.key);
    })
  }

  @Builder
  private MemberIconButton(icon: Resource, enabled: boolean, rotateUp: boolean, action: string, candidateKey: string) {
    Button() {
      Image(icon)
        .width(14)
        .height(14)
        .fillColor(action === 'remove' ? AppColor.danger : AppColor.textSecondary)
        .rotate({ angle: rotateUp ? 180 : 0 })
    }
    .width(28)
    .height(28)
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.35)
    .backgroundColor(action === 'remove' ? AppColor.dangerTint : AppColor.surfaceAlt)
    .borderRadius(14)
    .onClick(() => {
      this.handleMemberAction(action, candidateKey);
    })
  }

  @Builder
  private RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(AppColor.divider)
      .margin({ left: Space.lg })
  }

  @Builder
  private EmptyState() {
    Column({ space: Space.md }) {
      Image($r('app.media.ic_route'))
        .width(48)
        .height(48)
        .fillColor(AppColor.textTertiary)
        .opacity(0.35)
      Text(this.t('advancedOutbound.empty'))
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textTertiary)
        .textAlign(TextAlign.Center)
        .lineHeight(16)
        .width('100%')
    }
    .width('100%')
    .padding({ left: Space.xxl, right: Space.xxl, top: Space.xxxl, bottom: Space.xxxl })
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .margin({ left: Space.lg, right: Space.lg })
  }

  private async loadState(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.language = (await SETTINGS_CONTROLLER.load(context)).language;
      if (this.nodeName.trim().length === 0) {
        this.nodeName = this.mode === 'policy-group' ? this.t('advancedOutbound.defaultPolicyGroupName') : this.t('advancedOutbound.defaultProxyChainName');
      }
      const profile = await SubscriptionStore.load(context);
      this.candidates = this.collectCandidates(profile);
      this.selectedNodeKeys = this.filterExistingSelection(this.selectedNodeKeys);
    } catch (error) {
      this.lastError = this.f1('advancedOutbound.loadFailed', 'error', JSON.stringify(error));
    }
  }

  private collectCandidates(profile: SubscriptionProfile): Array<AdvancedOutboundCandidate> {
    const candidates = new Array<AdvancedOutboundCandidate>();
    for (let groupIndex = 0; groupIndex < profile.groups.length; groupIndex++) {
      const group = profile.groups[groupIndex];
      for (let nodeIndex = 0; nodeIndex < group.nodes.length; nodeIndex++) {
        const node = group.nodes[nodeIndex];
        if (isAdvancedOutboundBuildableNode(node)) {
          candidates.push({
            key: `${group.id}:${node.id}`,
            groupName: group.name,
            node: node
          });
        }
      }
    }

    if (candidates.length === 0) {
      for (let nodeIndex = 0; nodeIndex < profile.nodes.length; nodeIndex++) {
        const node = profile.nodes[nodeIndex];
        if (isAdvancedOutboundBuildableNode(node)) {
          candidates.push({
            key: `current:${node.id}`,
            groupName: this.t('advancedOutbound.currentGroup'),
            node: node
          });
        }
      }
    }
    return candidates;
  }

  private filterExistingSelection(keys: Array<string>): Array<string> {
    const filtered = new Array<string>();
    for (let index = 0; index < keys.length; index++) {
      if (this.findCandidate(keys[index]) !== null) {
        filtered.push(keys[index]);
      }
    }
    return filtered;
  }

  private canSave(): boolean {
    return !this.isBusy && this.selectedNodeKeys.length >= this.requiredMemberCount();
  }

  private requiredMemberCount(): number {
    return this.mode === 'policy-group' ? 1 : 2;
  }

  private pageTitle(): string {
    return this.mode === 'policy-group' ? this.t('advancedOutbound.policyGroup') : this.t('advancedOutbound.proxyChain');
  }

  private strategyLabel(strategy: string): string {
    if (strategy === 'random') {
      return this.t('advancedOutbound.strategy.random');
    }
    if (strategy === 'leastPing') {
      return this.t('advancedOutbound.strategy.leastPing');
    }
    if (strategy === 'leastLoad') {
      return this.t('advancedOutbound.strategy.leastLoad');
    }
    return this.t('advancedOutbound.strategy.roundRobin');
  }

  private candidateSubtitle(candidate: AdvancedOutboundCandidate): string {
    return `${candidate.groupName} / ${candidate.node.protocol.toUpperCase()}`;
  }

  private candidateIndex(key: string): number {
    for (let index = 0; index < this.candidates.length; index++) {
      if (this.candidates[index].key === key) {
        return index;
      }
    }
    return -1;
  }

  private isCandidateSelected(key: string): boolean {
    return this.selectedNodeKeys.indexOf(key) >= 0;
  }

  private selectedOrder(key: string): number {
    const index = this.selectedNodeKeys.indexOf(key);
    return index >= 0 ? index + 1 : 0;
  }

  private selectedCandidates(): Array<AdvancedOutboundCandidate> {
    const selected = new Array<AdvancedOutboundCandidate>();
    for (let index = 0; index < this.selectedNodeKeys.length; index++) {
      const candidate = this.findCandidate(this.selectedNodeKeys[index]);
      if (candidate !== null) {
        selected.push(candidate);
      }
    }
    return selected;
  }

  private selectedNodes(): Array<ProxyNode> {
    const selected = new Array<ProxyNode>();
    const candidates = this.selectedCandidates();
    for (let index = 0; index < candidates.length; index++) {
      selected.push(candidates[index].node);
    }
    return selected;
  }

  private findCandidate(key: string): AdvancedOutboundCandidate | null {
    for (let index = 0; index < this.candidates.length; index++) {
      if (this.candidates[index].key === key) {
        return this.candidates[index];
      }
    }
    return null;
  }

  private toggleCandidate(key: string): void {
    const next = this.selectedNodeKeys.slice();
    const index = next.indexOf(key);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(key);
    }
    this.selectedNodeKeys = next;
    this.lastError = '';
  }

  private handleMemberAction(action: string, key: string): void {
    if (action === 'remove') {
      this.toggleCandidate(key);
      return;
    }

    const next = this.selectedNodeKeys.slice();
    const index = next.indexOf(key);
    if (index < 0) {
      return;
    }
    if (action === 'up' && index > 0) {
      const previous = next[index - 1];
      next[index - 1] = next[index];
      next[index] = previous;
    } else if (action === 'down' && index < next.length - 1) {
      const following = next[index + 1];
      next[index + 1] = next[index];
      next[index] = following;
    }
    this.selectedNodeKeys = next;
  }

  private async saveAdvancedOutbound(): Promise<void> {
    if (!this.canSave()) {
      return;
    }

    this.isBusy = true;
    this.lastError = '';
    try {
      const nodes = this.selectedNodes();
      const result = this.mode === 'policy-group' ?
        buildPolicyGroupConfigFromNodes(this.nodeName, this.strategy, nodes) :
        buildProxyChainConfigFromNodes(this.nodeName, nodes);
      if (!result.success) {
        this.lastError = localizeCoreMessage(this.language, result.message);
        return;
      }

      const context = getContext(this) as common.Context;
      const saved = await NODES_CONTROLLER.saveProfile(context, result.configJson, this.language, result.configType);
      if (saved.profile === null) {
        this.lastError = saved.lastError;
        return;
      }

      await SubscriptionStore.addManualNode(context, result.name, saved.profile.outboundJson, saved.profile.configType);
      SHARED_RUNTIME_CONTROLLER.appendLog(`${result.configType} advanced outbound saved`);
      promptAction.showToast({ message: this.t('advancedOutbound.saved') });
      router.back();
    } catch (error) {
      this.lastError = this.f1('advancedOutbound.saveFailed', 'error', JSON.stringify(error));
    } finally {
      this.isBusy = false;
    }
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
}
