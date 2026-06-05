import { AppLanguage } from '../../core/Profile';
import { translate } from '../../core/I18n';
import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';

@Component
export struct AssetAddEditDialog {
  @Prop language: AppLanguage;
  @Prop title: string;
  @Prop initialName: string;
  @Prop initialUrl: string;
  
  @State inputName: string = '';
  @State inputUrl: string = '';

  onCancel: () => void = () => {};
  onConfirm: (name: string, url: string) => void = (name, url) => {};

  aboutToAppear() {
    this.inputName = this.initialName;
    this.inputUrl = this.initialUrl;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  build() {
    Stack() {
      // 遮罩层
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick(() => {
          this.onCancel();
        })

      // 弹窗主体
      Column({ space: Space.lg }) {
        Text(this.title)
          .fontSize(FontSz.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)

        Column({ space: Space.sm }) {
          Text(this.t('assets.urlName'))
            .fontSize(FontSz.footnote)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textSecondary)
            .alignSelf(ItemAlign.Start)
          TextInput({ text: this.inputName, placeholder: 'e.g. custom_geo' })
            .height(44)
            .fontSize(FontSz.body)
            .fontColor(AppColor.textPrimary)
            .placeholderColor(AppColor.textTertiary)
            .backgroundColor(AppColor.surfaceAlt)
            .borderRadius(Radius.md)
            .onChange((val) => this.inputName = val)

          Text(this.t('assets.urlAddress'))
            .fontSize(FontSz.footnote)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textSecondary)
            .alignSelf(ItemAlign.Start)
            .margin({ top: Space.xs })
          TextInput({ text: this.inputUrl, placeholder: 'https://...' })
            .height(44)
            .fontSize(FontSz.body)
            .fontColor(AppColor.textPrimary)
            .placeholderColor(AppColor.textTertiary)
            .backgroundColor(AppColor.surfaceAlt)
            .borderRadius(Radius.md)
            .enabled(!this.inputUrl.startsWith('local://'))
            .onChange((val) => this.inputUrl = val)
        }

        Row({ space: Space.md }) {
          Button(this.t('action.cancel'))
            .layoutWeight(1)
            .backgroundColor(AppColor.surfaceAlt)
            .fontColor(AppColor.textSecondary)
            .height(44)
            .borderRadius(Radius.pill)
            .onClick(() => {
              this.onCancel();
            })

          Button(this.t('action.save'))
            .layoutWeight(1)
            .backgroundColor(AppColor.brand)
            .fontColor(AppColor.onBrand)
            .height(44)
            .borderRadius(Radius.pill)
            .onClick(() => {
              this.onConfirm(this.inputName, this.inputUrl);
            })
        }
      }
      .width('85%')
      .padding(Space.xl)
      .backgroundColor(AppColor.surface)
      .borderRadius(Radius.lg)
    }
    .width('100%')
    .height('100%')
  }
}
