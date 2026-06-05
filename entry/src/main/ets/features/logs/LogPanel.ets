import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';

export type ClearLogHandler = () => void;

@Component
export struct RuntimeLogPanel {
  clearLabel: string = '';
  items: Array<string> = [];
  onClear: ClearLogHandler = () => {};

  build() {
    Column({ space: Space.md }) {
      Row() {
        Blank()
        Button(this.clearLabel)
          .height(30)
          .fontSize(FontSz.footnote)
          .backgroundColor(AppColor.surfaceAlt)
          .fontColor(AppColor.textSecondary)
          .borderRadius(Radius.sm)
          .padding({ left: Space.md, right: Space.md })
          .onClick(() => {
            this.onClear();
          })
      }
      .width('100%')

      Column({ space: Space.sm }) {
        ForEach(this.items, (item: string, index: number) => {
          Text(item)
            .fontSize(FontSz.footnote)
            .fontColor(index === 0 ? AppColor.textPrimary : AppColor.textTertiary)
            .width('100%')
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .padding(Space.md)
      .backgroundColor(AppColor.surfaceAlt)
      .borderRadius(Radius.md)
      .constraintSize({ minHeight: 120 })
    }
    .width('100%')
    .padding(Space.lg)
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .margin({ left: Space.lg, right: Space.lg })
  }
}
