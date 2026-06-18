import {
  CONTROL_CARD_SCAN_URI,
  CONTROL_CARD_START_URI,
  CONTROL_CARD_STOP_URI,
  CONTROL_CARD_TOGGLE_URI,
  buildControlCardFormData
} from '../../core/ControlCard';

let storage = new LocalStorage(buildControlCardFormData());

@Entry(storage)
@Component
struct HeyControlCard {
  @LocalStorageProp('appName') appName: string = 'Hey';
  @LocalStorageProp('subtitle') subtitle: string = 'Quick proxy controls';
  @LocalStorageProp('toggleUri') toggleUri: string = CONTROL_CARD_TOGGLE_URI;
  @LocalStorageProp('startUri') startUri: string = CONTROL_CARD_START_URI;
  @LocalStorageProp('stopUri') stopUri: string = CONTROL_CARD_STOP_URI;
  @LocalStorageProp('scanUri') scanUri: string = CONTROL_CARD_SCAN_URI;

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.appName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2937')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank()

        Text($r('app.string.control_card_badge'))
          .fontSize(11)
          .fontColor('#9A3412')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#FED7AA')
          .borderRadius(10)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.control_card_title'))
        .fontSize(14)
        .fontColor('#374151')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text($r('app.string.control_card_hint'))
        .fontSize(11)
        .fontColor('#6B7280')
        .lineHeight(15)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        this.primaryAction(this.toggleUri)
        this.secondaryAction(this.scanUri)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.smallAction(this.startUri, $r('app.string.control_card_start'))
        this.smallAction(this.stopUri, $r('app.string.control_card_stop'))
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#FFF7ED')
  }

  @Builder
  private primaryAction(uri: string) {
    FormLink({
      action: 'router',
      uri
    }) {
      Text($r('app.string.control_card_toggle'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(38)
        .lineHeight(38)
        .backgroundColor('#F97316')
        .borderRadius(12)
    }
    .layoutWeight(1)
  }

  @Builder
  private secondaryAction(uri: string) {
    FormLink({
      action: 'router',
      uri
    }) {
      Text($r('app.string.control_card_scan'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#EA580C')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(38)
        .lineHeight(38)
        .backgroundColor('#FFEDD5')
        .borderRadius(12)
    }
    .layoutWeight(1)
  }

  @Builder
  private smallAction(uri: string, label: ResourceStr) {
    FormLink({
      action: 'router',
      uri
    }) {
      Text(label)
        .fontSize(12)
        .fontColor('#7C2D12')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(30)
        .lineHeight(30)
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
        .borderWidth(1)
        .borderColor('#FDBA74')
    }
    .layoutWeight(1)
  }
}
