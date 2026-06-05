import { FlagTile, MetricTile } from '../../components/StatusTiles';
import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';

@Component
export struct RuntimeStatusPanel {
  durationLabel: string = '';
  durationValue: string = '';
  uploadLabel: string = '';
  uploadValue: string = '';
  downloadLabel: string = '';
  downloadValue: string = '';
  xrayActive: boolean = false;
  tunActive: boolean = false;
  lastMessage: string = '';

  build() {
    Column({ space: Space.md }) {
      Row({ space: Space.sm }) {
        MetricTile({ label: this.durationLabel, value: this.durationValue })
        MetricTile({ label: this.uploadLabel, value: this.uploadValue })
        MetricTile({ label: this.downloadLabel, value: this.downloadValue })
      }
      .width('100%')

      Row({ space: Space.sm }) {
        FlagTile({ label: 'Xray', active: this.xrayActive })
        FlagTile({ label: 'TUN', active: this.tunActive })
      }
      .width('100%')

      Text(this.lastMessage)
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textTertiary)
        .width('100%')
    }
    .width('100%')
    .padding(Space.lg)
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .margin({ left: Space.lg, right: Space.lg })
  }
}
