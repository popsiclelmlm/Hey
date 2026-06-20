import { router } from '@kit.ArkUI';
import { IconButton } from '../components/IconButton';
import { AppColor, FontSz, Radius } from '../theme/Theme';

@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop showBack: boolean = true;
  @Prop statusLabel: string = '';
  @Prop statusColor: ResourceColor = AppColor.textSecondary;
  @Prop statusBackground: ResourceColor = AppColor.surfaceAlt;
  onBack: () => void = () => {
    router.back();
  };
  @BuilderParam rightActions?: () => void;

  build() {
    Column() {
      Stack() {
        // 1. 居中标题
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(FontSz.headline)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('100%')
          if (this.summary.length > 0) {
            Text(this.summary)
              .fontSize(FontSz.caption)
              .fontColor(AppColor.textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 72, right: 96 })
        .hitTestBehavior(HitTestMode.Transparent)

        // 2. 左侧返回
        if (this.showBack) {
          Row() {
            IconButton({
              icon: $r('app.media.ic_arrow_back'),
              buttonSize: 44,
              iconSize: 26,
              iconColor: AppColor.textPrimary,
              onAction: () => {
                this.onBack();
              }
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: 8 })
        }

        // 3. 右侧操作 / 状态
        Row() {
          if (this.rightActions) {
            this.rightActions()
          } else if (this.statusLabel.length > 0) {
            Text(this.statusLabel)
              .fontSize(FontSz.footnote)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.statusColor)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(this.statusBackground)
              .borderRadius(Radius.md)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColor.surface)

      Divider()
        .strokeWidth(0.5)
        .color(AppColor.divider)
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
  }
}
