import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { picker } from '@kit.CoreFileKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { normalizeScannedAssetUrl } from '../core/AssetUrls';
import { buildBuiltinGeoAssetUrl, GEOIP_FILE_NAME, GEOIP_ONLY_CN_PRIVATE_FILE_NAME, GEOSITE_FILE_NAME } from '../core/GeoAssets';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { AssetStore, CustomAssetUrl } from '../storage/AssetStore';
import { ASSETS_CONTROLLER, GEO_SOURCES } from '../features/assets/AssetsController';
import { BuiltinGeoCard } from './assets/BuiltinGeoCard';
import { CustomAssetList } from './assets/CustomAssetList';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct AssetsPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;

  // 文件状态信息
  @State private geositeStatus: string = '';
  @State private geoipStatus: string = '';
  @State private geoipOnlyCnPrivateStatus: string = '';

  // 自定义 URL 管理视图控制
  @State private showCustomUrls: boolean = false;
  @State private customAssets: Array<CustomAssetUrl> = [];

  // 下载状态
  @State private downloadingFile: string = '';

  // 下载源管理
  @State private currentSourceUrl: string = GEO_SOURCES[0].url;
  @State private currentSourceName: string = GEO_SOURCES[0].name;

  // 暂存本地导入的 URI，双向绑定传递给 CustomAssetList
  @State private tempImportUri: string = '';
  @State private tempAssetName: string = '';
  @State private tempAssetUrl: string = '';
  @State private isStateLoaded: boolean = false;

  aboutToAppear(): void {
    this.loadState();
    this.loadCustomAssets();
  }

  build() {
    Stack() {
      if (!this.isStateLoaded) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(AppColor.brand)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(AppColor.bg)
      } else if (!this.showCustomUrls) {
        // 主视图
        Column() {
          PageHeader({
            title: this.t('screen.assets.title'),
            summary: this.t('assets.section.detail'),
            showBack: true
          })

          Scroll() {
            Column({ space: Space.lg }) {

              // 快捷操作
              SectionHeader({ title: this.t('assets.quickActions.title') })
              Column() {
                this.EntryRow(
                  $r('app.media.ic_refresh'), AppColor.brand, AppColor.brandTint,
                  this.t('assets.action.updateAll'), this.t('assets.action.updateAll.detail'), false,
                  () => this.downloadAllAssets()
                )
                this.RowDivider()
                this.EntryRow(
                  $r('app.media.ic_folder'), AppColor.textSecondary, AppColor.surfaceAlt,
                  this.t('assets.action.importLocal'), this.t('assets.action.importLocal.detail'), false,
                  () => this.importLocalFile()
                )
                this.RowDivider()
                this.EntryRow(
                  $r('app.media.ic_qr_code'), AppColor.success, AppColor.successTint,
                  this.t('assets.action.scanQr'), this.t('assets.action.scanQr.detail'), false,
                  () => this.scanAssetUrlFromQr()
                )
              }
              .width('100%')
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .clip(true)
              .margin({ left: Space.lg, right: Space.lg })

              // 内置 Geo 资源
              SectionHeader({ title: this.t('assets.builtin.title'), detail: this.t('assets.source.detail') })
              BuiltinGeoCard({
                language: this.language,
                geositeStatus: this.geositeStatus,
                geoipStatus: this.geoipStatus,
                geoipOnlyCnPrivateStatus: this.geoipOnlyCnPrivateStatus,
                currentSourceName: this.currentSourceName,
                currentSourceUrl: this.currentSourceUrl,
                downloadingFile: this.downloadingFile,
                onDownload: (fileName) => this.downloadAsset(fileName),
                onChangeSource: () => this.changeSource(),
                onDeleteAsset: (fileName) => this.deleteAsset(fileName)
              })

              // 自定义资源 URL
              SectionHeader({ title: this.t('assets.userUrls.title') })
              Column() {
                this.EntryRow(
                  $r('app.media.ic_link'), AppColor.success, AppColor.successTint,
                  this.t('assets.userUrls.title'),
                  this.f1('assets.userUrls.countDetail', 'count', this.customAssets.length.toString()),
                  true,
                  () => { this.showCustomUrls = true; }
                )
              }
              .width('100%')
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .clip(true)
              .margin({ left: Space.lg, right: Space.lg })

            }
            .width('100%')
            .padding({ top: Space.sm, bottom: Space.xxl })
          }
          .layoutWeight(1)
          .width('100%')
        }
        .height('100%')
        .width('100%')
        .backgroundColor(AppColor.bg)
      } else {
        // 自定义 URL 管理视图
        CustomAssetList({
          language: this.language,
          customAssets: $customAssets,
          tempImportUri: $tempImportUri,
          tempAssetName: $tempAssetName,
          tempAssetUrl: $tempAssetUrl,
          onBack: () => {
            this.showCustomUrls = false;
            this.updateFileStatus();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(AppColor.divider)
      .margin({ left: Space.lg })
  }

  @Builder
  private EntryRow(icon: Resource, iconColor: ResourceColor, iconBg: ResourceColor,
                   title: string, subtitle: string, showChevron: boolean, onTap: () => void) {
    Row({ space: Space.md }) {
      Row() {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor(iconColor)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(iconBg)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(subtitle)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (showChevron) {
        Image($r('app.media.ic_chevron_right'))
          .width(20)
          .height(20)
          .fillColor(AppColor.textTertiary)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      onTap();
    })
  }

  // 执行资源网络更新下载
  private async downloadAsset(fileName: string): Promise<void> {
    if (this.downloadingFile.length > 0) {
      promptAction.showToast({ message: this.t('assets.downloadBusy') });
      return;
    }
    const context = getContext(this) as common.Context;
    await ASSETS_CONTROLLER.downloadAsset(
      context,
      fileName,
      buildBuiltinGeoAssetUrl(this.currentSourceUrl, fileName),
      this.language,
      () => {
        this.downloadingFile = fileName;
        this.updateFileStatus();
      },
      () => {},
      () => {},
      () => {
        this.downloadingFile = '';
        this.updateFileStatus();
      }
    );
  }

  // 顺序一键更新全部 Geo 资源
  private async downloadAllAssets(): Promise<void> {
    if (this.downloadingFile.length > 0) {
      promptAction.showToast({ message: this.t('assets.downloadBusy') });
      return;
    }
    const context = getContext(this) as common.Context;
    this.downloadingFile = GEOSITE_FILE_NAME;
    this.updateFileStatus();
    await ASSETS_CONTROLLER.downloadAllAssets(
      context,
      this.currentSourceUrl,
      this.language,
      (fileName) => {
        this.downloadingFile = fileName;
        this.updateFileStatus();
      },
      (_successGeosite: boolean, _successGeoip: boolean, _successGeoipOnlyCnPrivate: boolean) => {
        this.downloadingFile = '';
        this.updateFileStatus();
      }
    );
  }

  // 调起系统 Picker 导入本地 .dat 文件
  private async importLocalFile(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.fileSuffixFilters = ['.dat'];
      documentSelectOptions.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.select(documentSelectOptions);
      if (!uris || uris.length === 0) {
        return;
      }
      const fileUri = uris[0];

      const menu: [promptAction.Button, promptAction.Button, promptAction.Button, promptAction.Button] = [
        { text: this.t('assets.importType.geosite'), color: AppColor.brand } as promptAction.Button,
        { text: this.t('assets.importType.geoip'), color: AppColor.brand } as promptAction.Button,
        { text: this.t('assets.importType.geoipOnlyCnPrivate'), color: AppColor.brand } as promptAction.Button,
        { text: this.t('assets.importType.custom'), color: AppColor.brand } as promptAction.Button
      ];

      promptAction.showActionMenu({
        title: this.t('assets.selectImportType'),
        buttons: menu
      }).then(async (result) => {
        const context = getContext(this) as common.Context;
        if (result.index === 0) {
          await ASSETS_CONTROLLER.copyLocalFileToAssets(context, fileUri, GEOSITE_FILE_NAME, this.language, () => this.updateFileStatus(), () => {});
        } else if (result.index === 1) {
          await ASSETS_CONTROLLER.copyLocalFileToAssets(context, fileUri, GEOIP_FILE_NAME, this.language, () => this.updateFileStatus(), () => {});
        } else if (result.index === 2) {
          await ASSETS_CONTROLLER.copyLocalFileToAssets(context, fileUri, GEOIP_ONLY_CN_PRIVATE_FILE_NAME, this.language, () => this.updateFileStatus(), () => {});
        } else if (result.index === 3) {
          // 自定义本地规则导入：记录临时 URI，并跳转到自定义列表以触发弹窗输入
          this.tempImportUri = fileUri;
          this.tempAssetName = '';
          this.tempAssetUrl = '';
          this.showCustomUrls = true;
        }
      });
    } catch (error) {
      promptAction.showToast({ message: this.f1('assets.openPickerFailed', 'error', JSON.stringify(error)) });
    }
  }

  private async scanAssetUrlFromQr(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(context, options);
      if (!result || !result.originalValue || result.originalValue.trim().length === 0) {
        return;
      }

      const assetUrl = normalizeScannedAssetUrl(result.originalValue);
      if (!assetUrl.valid) {
        promptAction.showToast({ message: this.t('assets.scanInvalidUrl') });
        return;
      }

      this.tempImportUri = '';
      this.tempAssetName = assetUrl.name;
      this.tempAssetUrl = assetUrl.url;
      this.showCustomUrls = true;
    } catch (error) {
      const errorRecord = error as Record<string, Object>;
      const code = errorRecord['code'];
      if (code === 20001 || code === '20001') {
        return;
      }
      promptAction.showToast({ message: this.f1('assets.scanFailed', 'error', JSON.stringify(error)) });
    }
  }

  // 切换下载源
  private changeSource(): void {
    const buttons = new Array<promptAction.Button>();
    for (let index = 0; index < GEO_SOURCES.length; index++) {
      buttons.push({ text: GEO_SOURCES[index].name, color: AppColor.brand } as promptAction.Button);
    }

    promptAction.showActionMenu({
      title: this.t('assets.source.title'),
      buttons: this.toActionMenuButtons(buttons)
    }).then(async (result) => {
      if (result.index >= 0 && result.index < GEO_SOURCES.length) {
        const selected = GEO_SOURCES[result.index];
        this.currentSourceUrl = selected.url;
        this.currentSourceName = selected.name;

        const context = getContext(this) as common.Context;
        const assetStore = await preferences.getPreferences(context, 'hey_vpn_assets');
        await assetStore.put('geo_source_url', this.currentSourceUrl);
        await assetStore.flush();
        promptAction.showToast({ message: this.f1('assets.source.changed', 'name', selected.name) });
      }
    });
  }

  private toActionMenuButtons(buttons: Array<promptAction.Button>): [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] {
    return buttons as [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?];
  }

  // 删除 Geo 资源
  private deleteAsset(fileName: string): void {
    const context = getContext(this) as common.Context;
    ASSETS_CONTROLLER.deleteAsset(context, fileName, this.language, () => this.updateFileStatus());
  }

  private updateFileStatus(): void {
    const context = getContext(this) as common.Context;
    this.geositeStatus = ASSETS_CONTROLLER.getFileStatus(context, GEOSITE_FILE_NAME, this.language);
    this.geoipStatus = ASSETS_CONTROLLER.getFileStatus(context, GEOIP_FILE_NAME, this.language);
    this.geoipOnlyCnPrivateStatus = ASSETS_CONTROLLER.getFileStatus(context, GEOIP_ONLY_CN_PRIVATE_FILE_NAME, this.language);
  }

  // 加载自定义 Geo 链接
  private async loadCustomAssets(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.customAssets = await AssetStore.load(context);
  }

  private async loadState(): Promise<void> {
    this.isStateLoaded = false;
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;

    // 从 preferences 加载下载源
    const assetStore = await preferences.getPreferences(context, 'hey_vpn_assets');
    const sourceUrl = await assetStore.get('geo_source_url', GEO_SOURCES[0].url);
    this.currentSourceUrl = sourceUrl.toString();
    const found = GEO_SOURCES.find(s => s.url === this.currentSourceUrl);
    this.currentSourceName = found ? found.name : GEO_SOURCES[0].name;
    this.updateFileStatus();
    this.isStateLoaded = true;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
