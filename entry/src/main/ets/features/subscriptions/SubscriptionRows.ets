import { ProxyNode, SubscriptionGroup } from '../../core/Profile';
import { IconButton } from '../../components/IconButton';
import { ProxyNodeHandler } from '../servers/ServerCard';
import { AppColor, FontSz, Space } from '../../theme/Theme';

export type SubscriptionGroupHandler = (group: SubscriptionGroup) => void;

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

const EMPTY_GROUP: SubscriptionGroup = {
  id: '',
  name: '',
  url: '',
  enabled: false,
  selectedNodeId: '',
  nodes: [],
  updatedAt: 0
};

@Component
export struct SubscriptionGroupListRow {
  group: SubscriptionGroup = EMPTY_GROUP;
  @Prop isSelected: boolean = false;
  @Prop summary: string = '';
  @Prop currentLabel: string = '';
  @Prop openLabel: string = '';
  @Prop onLabel: string = '';
  @Prop offLabel: string = '';
  @Prop deleteLabel: string = '';
  onSelect: SubscriptionGroupHandler = (_group: SubscriptionGroup) => {};
  onToggle: SubscriptionGroupHandler = (_group: SubscriptionGroup) => {};
  onDelete: SubscriptionGroupHandler = (_group: SubscriptionGroup) => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.group.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.summary)
            .fontSize(13)
            .fontColor(AppColor.textSecondary)
        }
        .layoutWeight(1)

        IconButton({
          icon: this.isSelected ? $r('app.media.ic_check') : $r('app.media.ic_chevron_right'),
          buttonSize: 42,
          iconSize: this.isSelected ? 22 : 28,
          iconColor: this.isSelected ? AppColor.onBrand : AppColor.textPrimary,
          buttonBackground: this.isSelected ? AppColor.brand : '#00000000',
          onAction: () => {
            this.onSelect(this.group);
          }
        })
        Toggle({ type: ToggleType.Switch, isOn: this.group.enabled })
          .selectedColor(AppColor.brand)
          .switchPointColor(AppColor.onBrand)
          .onChange((_isOn: boolean) => {
            this.onToggle(this.group);
          })
        IconButton({
          icon: $r('app.media.ic_delete'),
          buttonSize: 42,
          iconSize: 24,
          iconColor: AppColor.textPrimary,
          onAction: () => {
            this.onDelete(this.group);
          }
        })
      }
      .width('100%')
      .padding({ left: 24, right: 12, top: 14, bottom: 14 })
      Divider()
        .strokeWidth(1)
        .color(AppColor.divider)
        .margin({ left: 24 })
    }
    .width('100%')
    .backgroundColor(this.isSelected ? AppColor.brandTint : AppColor.surface)
  }
}

@Component
export struct SubscriptionNodeListRow {
  node: ProxyNode = EMPTY_NODE;
  @Prop isSelected: boolean = false;
  @Prop isBusy: boolean = false;
  @Prop delayText: string = '';
  @Prop delayColor: string = '#6B7280';
  @Prop selectedLabel: string = '';
  @Prop useLabel: string = '';
  onSelect: ProxyNodeHandler = (_node: ProxyNode) => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.node.name)
            .fontSize(FontSz.callout)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.node.protocol.toUpperCase())
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.brand)
        }
        .layoutWeight(1)

        Text(this.delayText)
          .fontSize(FontSz.footnote)
          .fontColor(this.delayColor)
          .width(82)
          .textAlign(TextAlign.Center)

        IconButton({
          icon: $r('app.media.ic_check'),
          buttonSize: 42,
          iconSize: 22,
          iconColor: this.isSelected ? AppColor.onBrand : AppColor.textPrimary,
          buttonBackground: this.isSelected ? AppColor.brand : '#00000000',
          isEnabled: !this.isBusy,
          onAction: () => {
            this.onSelect(this.node);
          }
        })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.md, top: Space.md, bottom: Space.md })
      Divider()
        .strokeWidth(0.5)
        .color(AppColor.divider)
        .margin({ left: Space.lg })
    }
    .width('100%')
    .backgroundColor(this.isSelected ? AppColor.brandTint : AppColor.surface)
  }
}
