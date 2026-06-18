import { promptAction } from '@kit.ArkUI';
import { AppLanguage, RoutingRule } from '../../core/Profile';
import { translate } from '../../core/I18n';
import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';

@Component
export struct RoutingRuleDialog {
  @Prop language: AppLanguage;
  @Prop title: string;
  @Prop initialRule: RoutingRule;

  @State private remarks: string = '';
  @State private domain: string = '';
  @State private ip: string = '';
  @State private process: string = '';
  @State private port: string = '';
  @State private protocol: string = '';
  @State private network: string = '';
  @State private outboundTag: string = 'proxy';
  @State private enabled: boolean = true;

  onCancel: () => void = () => {};
  onConfirm: (rule: RoutingRule) => void = (_rule: RoutingRule) => {};

  aboutToAppear(): void {
    this.remarks = this.initialRule.remarks;
    this.domain = this.initialRule.domain.join(',');
    this.ip = this.initialRule.ip.join(',');
    this.process = this.initialRule.process.join(',');
    this.port = this.initialRule.port;
    this.protocol = this.initialRule.protocol.join(',');
    this.network = this.initialRule.network;
    this.outboundTag = this.initialRule.outboundTag.length > 0 ? this.initialRule.outboundTag : 'proxy';
    this.enabled = this.initialRule.enabled;
  }

  build() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick(() => {
          this.onCancel();
        })

      Column({ space: Space.lg }) {
        Row() {
          Text(this.title)
            .fontSize(FontSz.headline)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.textPrimary)
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.enabled })
            .selectedColor(AppColor.brand)
            .switchPointColor(AppColor.onBrand)
            .onChange((isOn: boolean) => {
              this.enabled = isOn;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: Space.md }) {
            this.InputField(this.t('routing.rule.remarks'), this.remarks, this.t('routing.rule.remarks.placeholder'), 'remarks')
            this.InputField(this.t('routing.rule.domain'), this.domain, 'domain:example.com,geosite:cn', 'domain')
            this.InputField(this.t('routing.rule.ip'), this.ip, 'geoip:private,1.1.1.1', 'ip')
            this.InputField(this.t('routing.rule.process'), this.process, 'com.example.app', 'process')
            this.InputField(this.t('routing.rule.port'), this.port, '53,443,1000-2000', 'port')
            this.InputField(this.t('routing.rule.protocol'), this.protocol, 'http,tls,bittorrent', 'protocol')

            Column({ space: Space.sm }) {
              Text(this.t('routing.rule.network'))
                .fontSize(FontSz.footnote)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColor.textSecondary)
                .alignSelf(ItemAlign.Start)
              Row({ space: Space.sm }) {
                this.NetworkButton('', this.t('routing.rule.network.all'))
                this.NetworkButton('tcp', 'TCP')
                this.NetworkButton('udp', 'UDP')
              }
              .width('100%')
            }

            Column({ space: Space.sm }) {
              Text(this.t('routing.rule.outboundTag'))
                .fontSize(FontSz.footnote)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColor.textSecondary)
                .alignSelf(ItemAlign.Start)
              Row({ space: Space.sm }) {
                this.OutboundTagButton('proxy', this.t('routing.rule.target.proxy'))
                this.OutboundTagButton('direct', this.t('routing.rule.target.direct'))
                this.OutboundTagButton('block', this.t('routing.rule.target.block'))
              }
              .width('100%')
            }

            Text(this.t('routing.rule.matcherHint'))
              .fontSize(FontSz.caption)
              .fontColor(AppColor.textTertiary)
              .lineHeight(16)
              .width('100%')
          }
          .width('100%')
        }
        .height(430)
        .width('100%')
        .scrollBar(BarState.Off)

        Row({ space: Space.md }) {
          Button(this.t('action.cancel'))
            .layoutWeight(1)
            .height(44)
            .backgroundColor(AppColor.surfaceAlt)
            .fontColor(AppColor.textSecondary)
            .borderRadius(Radius.pill)
            .onClick(() => {
              this.onCancel();
            })

          Button(this.t('action.save'))
            .layoutWeight(1)
            .height(44)
            .backgroundColor(AppColor.brand)
            .fontColor(AppColor.onBrand)
            .borderRadius(Radius.pill)
            .onClick(() => {
              this.confirmRule();
            })
        }
        .width('100%')
      }
      .width('88%')
      .padding(Space.xl)
      .backgroundColor(AppColor.surface)
      .borderRadius(Radius.lg)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private InputField(label: string, value: string, placeholder: string, field: string) {
    Column({ space: Space.sm }) {
      Text(label)
        .fontSize(FontSz.footnote)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textSecondary)
        .alignSelf(ItemAlign.Start)
      TextInput({ text: value, placeholder: placeholder })
        .height(44)
        .fontSize(FontSz.body)
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .backgroundColor(AppColor.surfaceAlt)
        .borderRadius(Radius.md)
        .onChange((text: string) => {
          this.updateInput(field, text);
        })
    }
    .width('100%')
  }

  @Builder
  private NetworkButton(value: string, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(38)
      .fontSize(FontSz.footnote)
      .fontColor(this.network === value ? AppColor.onBrand : AppColor.textSecondary)
      .backgroundColor(this.network === value ? AppColor.brand : AppColor.surfaceAlt)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.network = value;
      })
  }

  @Builder
  private OutboundTagButton(value: string, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(38)
      .fontSize(FontSz.footnote)
      .fontColor(this.outboundTag === value ? AppColor.onBrand : AppColor.textSecondary)
      .backgroundColor(this.outboundTag === value ? AppColor.brand : AppColor.surfaceAlt)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.outboundTag = value;
      })
  }

  private confirmRule(): void {
    const remarks = this.remarks.trim();
    const rule: RoutingRule = {
      id: this.initialRule.id,
      remarks,
      domain: this.splitCsv(this.domain),
      ip: this.splitCsv(this.ip),
      process: this.splitCsv(this.process),
      outboundTag: this.outboundTag,
      port: this.port.trim(),
      network: this.network,
      protocol: this.splitCsv(this.protocol),
      enabled: this.enabled,
      locked: this.initialRule.locked
    };

    if (rule.remarks.length === 0) {
      promptAction.showToast({ message: this.t('routing.rule.error.remarks') });
      return;
    }
    if (!this.hasMatcher(rule)) {
      promptAction.showToast({ message: this.t('routing.rule.error.matcher') });
      return;
    }
    this.onConfirm(rule);
  }

  private updateInput(field: string, value: string): void {
    if (field === 'remarks') {
      this.remarks = value;
    } else if (field === 'domain') {
      this.domain = value;
    } else if (field === 'ip') {
      this.ip = value;
    } else if (field === 'process') {
      this.process = value;
    } else if (field === 'port') {
      this.port = value;
    } else if (field === 'protocol') {
      this.protocol = value;
    }
  }

  private hasMatcher(rule: RoutingRule): boolean {
    return rule.domain.length > 0 || rule.ip.length > 0 || rule.process.length > 0 ||
      rule.port.length > 0 || rule.protocol.length > 0 || rule.network.length > 0;
  }

  private splitCsv(value: string): string[] {
    const result = new Array<string>();
    const parts = value.split(',');
    for (let index = 0; index < parts.length; index++) {
      const item = parts[index].trim();
      if (item.length > 0 && result.indexOf(item) < 0) {
        result.push(item);
      }
    }
    return result;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }
}
