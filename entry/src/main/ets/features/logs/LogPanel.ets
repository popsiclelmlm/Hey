export type ClearLogHandler = () => void;

@Component
export struct RuntimeLogPanel {
  title: string = '';
  clearLabel: string = '';
  items: Array<string> = [];
  onClear: ClearLogHandler = () => {};

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .layoutWeight(1)
        Button(this.clearLabel)
          .height(32)
          .width(72)
          .fontSize(13)
          .backgroundColor('#E5E7EB')
          .fontColor('#374151')
          .borderRadius(6)
          .onClick(() => {
            this.onClear();
          })
      }
      .width('100%')

      Column({ space: 6 }) {
        ForEach(this.items, (item: string, index: number) => {
          Text(item)
            .fontSize(12)
            .fontColor(index === 0 ? '#111827' : '#4B5563')
            .width('100%')
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#F9FAFB')
      .borderRadius(6)
      .constraintSize({ minHeight: 120 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }
}
