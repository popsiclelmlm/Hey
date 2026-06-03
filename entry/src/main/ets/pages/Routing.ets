import { common } from '@kit.AbilityKit';
import { ActionListItem } from '../components/ActionListItem';
import { SectionHeader } from '../components/SectionHeader';
import { SelectionButton } from '../components/SelectionButton';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { SETTINGS_CONTROLLER, SettingsDraft } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct RoutingPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private trafficMode: string = 'rules';
  @State private routingStrategy: string = 'AsIs';
  private draft: SettingsDraft | null = null;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.routing.title'),
        summary: this.t(`routing.mode.${this.trafficMode}`),
        showBack: true
      })
      Scroll() {
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
  private TrafficModeButton(value: string, label: string) {
    SelectionButton({
      label,
      itemValue: value,
      isSelected: this.trafficMode === value,
      labelSize: 12,
      onSelect: (nextValue: string) => {
        this.trafficMode = nextValue;
        this.persistSettings(this.f1('log.routingStrategy', 'value', label));
      }
    })
  }

  @Builder
  private StrategyButton(value: string) {
    SelectionButton({
      label: value,
      itemValue: value,
      isSelected: this.routingStrategy === value,
      labelSize: 11,
      onSelect: (nextValue: string) => {
        this.routingStrategy = nextValue;
        this.persistSettings(this.f1('log.routingStrategy', 'value', nextValue));
      }
    })
  }

  @Builder
  private RoutingPreset(title: string, detail: string) {
    ActionListItem({
      title,
      detail,
      actionLabel: this.t('action.open'),
      onAction: (openedTitle: string) => {
        SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.presetOpened', 'title', openedTitle));
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
  }

  private async persistSettings(logMessage: string): Promise<void> {
    if (this.draft === null) {
      return;
    }
    this.draft.trafficMode = this.trafficMode;
    this.draft.routingDomainStrategy = this.routingStrategy;
    const context = getContext(this) as common.Context;
    const saved = await SETTINGS_CONTROLLER.save(context, this.draft);
    this.draft = SETTINGS_CONTROLLER.toDraft(saved);
    this.language = this.draft.language;
    SHARED_RUNTIME_CONTROLLER.appendLog(logMessage);
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
