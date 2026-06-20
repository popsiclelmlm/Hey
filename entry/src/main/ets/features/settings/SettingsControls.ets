import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';

export type ToggleSettingHandler = (action: string) => void;
export type TextSettingHandler = (action: string, value: string) => void;

@Component
export struct SettingToggleRow {
  @Prop title: string = '';
  @Prop settingKey: string = '';
  @Prop isEnabled: boolean = false;
  action: string = '';
  @Prop onLabel: string = '';
  @Prop offLabel: string = '';
  onToggle: ToggleSettingHandler = (_action: string) => {};

  build() {
    Row({ space: Space.md }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(FontSz.callout)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.settingKey.length > 0) {
          Text(this.settingKey)
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
        .selectedColor(AppColor.brand)
        .switchPointColor(AppColor.onBrand)
        .onChange((_isOn: boolean) => {
          this.onToggle(this.action);
        })
    }
    .width('100%')
    .height(54)
    .padding({ left: Space.lg, right: Space.lg })
    .backgroundColor(AppColor.surface)
  }
}

@Component
export struct SettingInputRow {
  @Prop title: string = '';
  @Prop settingKey: string = '';
  @Prop value: string = '';
  action: string = '';
  onChange: TextSettingHandler = (_action: string, _value: string) => {};

  build() {
    Column({ space: Space.sm }) {
      Text(this.title)
        .fontSize(FontSz.callout)
        .fontColor(AppColor.textPrimary)
        .width('100%')

      TextInput({ text: this.value, placeholder: this.title })
        .height(40)
        .width('100%')
        .fontSize(FontSz.body)
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .backgroundColor(AppColor.surfaceAlt)
        .borderRadius(Radius.md)
        .padding({ left: Space.md, right: Space.md })
        .onChange((next: string) => {
          this.onChange(this.action, next);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.md })
    .backgroundColor(AppColor.surface)
  }
}
