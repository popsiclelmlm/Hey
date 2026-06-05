import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { picker } from '@kit.CoreFileKit';
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

@Entry
@Component
struct AssetsPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;

  // 文件状态信息
  @State private geositeStatus: string = '';
  @State private geoipStatus: string = '';

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

  aboutToAppear(): void {
    this.loadState();
    this.loadCustomAssets();
  }

  build() {
    Stack() {
      if (!this.showCustomUrls) {
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
              SectionHeader({ title: '快捷操作' })
              Column() {
                this.EntryRow(
                  $r('app.media.ic_refresh'), AppColor.brand, AppColor.brandTint,
                  this.t('assets.action.updateAll'), '更新全部 Geo 规则资源', false,
                  () => this.downloadAllAssets()
                )
                this.RowDivider()
                this.EntryRow(
                  $r('app.media.ic_folder'), AppColor.textSecondary, AppColor.surfaceAlt,
                  this.t('assets.action.importLocal'), this.t('assets.action.importLocal.detail'), false,
                  () => this.importLocalFile()
                )
              }
              .width('100%')
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .clip(true)
              .margin({ left: Space.lg, right: Space.lg })

              // 内置 Geo 资源
              SectionHeader({ title: '内置 Geo 资源', detail: this.t('assets.source.detail') })
              BuiltinGeoCard({
                language: this.language,
                geositeStatus: this.geositeStatus,
                geoipStatus: this.geoipStatus,
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
                  `${this.t('assets.userUrls.detail')} (已配置 ${this.customAssets.length} 个)`,
                  true,
                  () => { this.showCustomUrls = true; }
                )
              }
              .width('100%')
              .backgroundColor(AppColor.surface)
              .borderRadius(Radius.lg)
              .clip(true)
              .margin({ left: Space.lg, right: Space.lg })

              // 备份与还原
              SectionHeader({ title: this.t('assets.backupRestore.title'), detail: this.t('assets.backupRestore.detail') })
              Column() {
                this.EntryRow(
                  $r('app.media.ic_share'), AppColor.brand, AppColor.brandTint,
                  '备份配置', '导出当前配置到剪贴板', false,
                  () => this.backupConfig()
                )
                this.RowDivider()
                this.EntryRow(
                  $r('app.media.ic_refresh'), AppColor.textSecondary, AppColor.surfaceAlt,
                  '还原配置', '从剪贴板读取并覆盖配置', false,
                  () => this.restoreConfig()
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
      .alignItems(HorizontalAlign.Center)

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
      promptAction.showToast({ message: '已有文件在下载中，请稍后' });
      return;
    }
    const context = getContext(this) as common.Context;
    await ASSETS_CONTROLLER.downloadAsset(
      context,
      fileName,
      `${this.currentSourceUrl}${fileName}`,
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
      promptAction.showToast({ message: '已有文件在下载中，请稍后' });
      return;
    }
    const context = getContext(this) as common.Context;
    this.downloadingFile = 'geosite.dat';
    this.updateFileStatus();
    await ASSETS_CONTROLLER.downloadAllAssets(
      context,
      this.currentSourceUrl,
      this.language,
      (fileName) => {
        this.downloadingFile = fileName;
        this.updateFileStatus();
      },
      (successGeosite, successGeoip) => {
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

      const menu: [promptAction.Button, promptAction.Button, promptAction.Button] = [
        { text: this.t('assets.importType.geosite'), color: AppColor.brand } as promptAction.Button,
        { text: this.t('assets.importType.geoip'), color: AppColor.brand } as promptAction.Button,
        { text: this.t('assets.importType.custom'), color: AppColor.brand } as promptAction.Button
      ];

      promptAction.showActionMenu({
        title: this.t('assets.selectImportType'),
        buttons: menu
      }).then(async (result) => {
        const context = getContext(this) as common.Context;
        if (result.index === 0) {
          await ASSETS_CONTROLLER.copyLocalFileToAssets(context, fileUri, 'geosite.dat', this.language, () => this.updateFileStatus(), () => {});
        } else if (result.index === 1) {
          await ASSETS_CONTROLLER.copyLocalFileToAssets(context, fileUri, 'geoip.dat', this.language, () => this.updateFileStatus(), () => {});
        } else if (result.index === 2) {
          // 自定义本地规则导入：记录临时 URI，并跳转到自定义列表以触发弹窗输入
          this.tempImportUri = fileUri;
          this.showCustomUrls = true;
        }
      });
    } catch (error) {
      promptAction.showToast({ message: `打开文件选择器失败: ${JSON.stringify(error)}` });
    }
  }

  // 切换下载源
  private changeSource(): void {
    const buttons: [promptAction.Button, promptAction.Button] = [
      { text: GEO_SOURCES[0].name, color: AppColor.brand } as promptAction.Button,
      { text: GEO_SOURCES[1].name, color: AppColor.brand } as promptAction.Button
    ];

    promptAction.showActionMenu({
      title: this.t('assets.source.title'),
      buttons: buttons
    }).then(async (result) => {
      if (result.index >= 0 && result.index < GEO_SOURCES.length) {
        const selected = GEO_SOURCES[result.index];
        this.currentSourceUrl = selected.url;
        this.currentSourceName = selected.name;

        const context = getContext(this) as common.Context;
        const assetStore = await preferences.getPreferences(context, 'hey_vpn_assets');
        await assetStore.put('geo_source_url', this.currentSourceUrl);
        await assetStore.flush();
        promptAction.showToast({ message: `下载源已切换为 ${selected.name}` });
      }
    });
  }

  // 删除 Geo 资源
  private deleteAsset(fileName: string): void {
    const context = getContext(this) as common.Context;
    ASSETS_CONTROLLER.deleteAsset(context, fileName, this.language, () => this.updateFileStatus());
  }

  private updateFileStatus(): void {
    const context = getContext(this) as common.Context;
    this.geositeStatus = ASSETS_CONTROLLER.getFileStatus(context, 'geosite.dat', this.language);
    this.geoipStatus = ASSETS_CONTROLLER.getFileStatus(context, 'geoip.dat', this.language);
  }

  // 加载自定义 Geo 链接
  private async loadCustomAssets(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.customAssets = await AssetStore.load(context);
  }

  // 配置一键备份到剪贴板
  private async backupConfig(): Promise<void> {
    const context = getContext(this) as common.Context;
    await ASSETS_CONTROLLER.backupConfig(context, this.language);
  }

  // 配置从剪贴板一键还原
  private async restoreConfig(): Promise<void> {
    const context = getContext(this) as common.Context;
    await ASSETS_CONTROLLER.restoreConfig(
      context,
      this.language,
      () => {
        this.loadState();
        this.loadCustomAssets();
      },
      () => {}
    );
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;

    // 从 preferences 加载下载源
    const assetStore = await preferences.getPreferences(context, 'hey_vpn_assets');
    const sourceUrl = await assetStore.get('geo_source_url', GEO_SOURCES[0].url);
    this.currentSourceUrl = sourceUrl.toString();
    const found = GEO_SOURCES.find(s => s.url === this.currentSourceUrl);
    this.currentSourceName = found ? found.name : GEO_SOURCES[0].name;

    this.updateFileStatus();
  }

  private t(key: string): string {
    return translate(this.language, key);
  }
}
