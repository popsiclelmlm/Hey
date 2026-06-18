import { DEFAULT_LANGUAGE } from '../../core/I18n';
import { AppLanguage } from '../../core/Profile';
import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';

export type ToggleSettingHandler = (action: string) => void;
export type TextSettingHandler = (action: string, value: string) => void;
export type LanguageSelectHandler = (language: AppLanguage) => void;

@Component
export struct SettingToggleRow {
  title: string = '';
  settingKey: string = '';
  isEnabled: boolean = false;
  action: string = '';
  onLabel: string = '';
  offLabel: string = '';
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
export struct LanguageToggleRow {
  title: string = '';
  settingKey: string = '';
  autoLabel: string = '';
  zhLabel: string = '';
  enLabel: string = '';
  language: AppLanguage = DEFAULT_LANGUAGE;
  onChange: LanguageSelectHandler = (_language: AppLanguage) => {};

  build() {
    Row({ space: Space.md }) {
      Text(this.title)
        .fontSize(FontSz.callout)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)

      Row() {
        this.SegItem(this.autoLabel, this.language === 'auto', () => {
          this.onChange('auto');
        })
        this.SegItem(this.zhLabel, this.language === 'zh', () => {
          this.onChange('zh');
        })
        this.SegItem(this.enLabel, this.language === 'en', () => {
          this.onChange('en');
        })
      }
      .padding(2)
      .backgroundColor(AppColor.surfaceAlt)
      .borderRadius(Radius.md)
    }
    .width('100%')
    .height(54)
    .padding({ left: Space.lg, right: Space.lg })
    .backgroundColor(AppColor.surface)
  }

  @Builder
  private SegItem(label: string, selected: boolean, action: () => void) {
    Text(label)
      .fontSize(FontSz.footnote)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(selected ? AppColor.onBrand : AppColor.textSecondary)
      .textAlign(TextAlign.Center)
      .height(28)
      .width(64)
      .borderRadius(Radius.sm)
      .backgroundColor(selected ? AppColor.brand : Color.Transparent)
      .onClick(() => {
        action();
      })
  }
}

@Component
export struct SettingInputRow {
  title: string = '';
  settingKey: string = '';
  value: string = '';
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
