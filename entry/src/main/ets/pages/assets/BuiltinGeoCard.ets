import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { GEOIP_FILE_NAME, GEOIP_ONLY_CN_PRIVATE_FILE_NAME, GEOSITE_FILE_NAME } from '../../core/GeoAssets';
import { AppLanguage } from '../../core/Profile';
import { translate } from '../../core/I18n';
import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';

@Component
export struct BuiltinGeoCard {
  @Prop language: AppLanguage;
  @Prop geositeStatus: string;
  @Prop geoipStatus: string;
  @Prop geoipOnlyCnPrivateStatus: string;
  @Prop currentSourceName: string;
  @Prop currentSourceUrl: string;
  @Prop downloadingFile: string;

  // 交互回调
  onDownload: (fileName: string) => void = () => {};
  onChangeSource: () => void = () => {};
  onDeleteAsset: (fileName: string) => void = () => {};

  private t(key: string): string {
    return translate(this.language, key);
  }

  build() {
    Column() {
      // 下载源选择行
      Row({ space: Space.md }) {
        Column({ space: 3 }) {
          Text(this.t('assets.source.title'))
            .fontSize(FontSz.callout)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
          Text(this.t('assets.source.detail'))
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: Space.xs }) {
          Text(this.currentSourceName)
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.brand)
            .fontWeight(FontWeight.Medium)
          Image($r('app.media.ic_arrow_downward'))
            .width(14)
            .height(14)
            .fillColor(AppColor.brand)
        }
        .backgroundColor(AppColor.surfaceAlt)
        .borderRadius(Radius.sm)
        .padding({ left: Space.sm, right: Space.sm, top: Space.xs + 2, bottom: Space.xs + 2 })
        .onClick(() => {
          this.onChangeSource();
        })
      }
      .width('100%')
      .padding(Space.lg)

      this.RowDivider()

      this.GeoItemRow(GEOSITE_FILE_NAME, this.geositeStatus)

      this.RowDivider()

      this.GeoItemRow(GEOIP_FILE_NAME, this.geoipStatus)

      this.RowDivider()

      this.GeoItemRow(GEOIP_ONLY_CN_PRIVATE_FILE_NAME, this.geoipOnlyCnPrivateStatus)
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })
  }

  @Builder
  private RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(AppColor.divider)
      .margin({ left: Space.lg })
  }

  @Builder
  private GeoItemRow(fileName: string, status: string) {
    Row({ space: Space.md }) {
      // 左边文件图标与文字描述
      Row() {
        Image($r('app.media.ic_article'))
          .width(20)
          .height(20)
          .fillColor(AppColor.brand)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.brandTint)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 3 }) {
        Text(fileName)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(status)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧操作
      if (this.downloadingFile === fileName) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppColor.brand)
      } else {
        Row({ space: Space.sm }) {
          Button() {
            Image($r('app.media.ic_cloud_download'))
              .width(20)
              .height(20)
              .fillColor(AppColor.brand)
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onDownload(fileName);
          })

          Button() {
            Image($r('app.media.ic_more_vert'))
              .width(20)
              .height(20)
              .fillColor(AppColor.textSecondary)
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.handleAssetMoreClick(fileName);
          })
        }
      }
    }
    .width('100%')
    .padding(Space.lg)
  }

  private handleAssetMoreClick(fileName: string): void {
    const context = getContext(this) as common.Context;
    const exists = this.checkFileExists(context, fileName);

    const menu: [promptAction.Button, promptAction.Button] = [
      { text: this.t('action.update'), color: AppColor.brand } as promptAction.Button,
      { text: this.t('action.del'), color: exists ? '#EF4444' : '#9CA3AF' } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: fileName,
      buttons: menu
    }).then((result) => {
      if (result.index === 0) {
        this.onDownload(fileName);
      } else if (result.index === 1 && exists) {
        this.onDeleteAsset(fileName);
      }
    });
  }

  private checkFileExists(context: common.Context, fileName: string): boolean {
    const path = `${context.filesDir}/${fileName}`;
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }
}
