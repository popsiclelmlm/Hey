import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { picker } from '@kit.CoreFileKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { normalizeScannedAssetUrl } from '../core/AssetUrls';
import { buildBuiltinGeoAssetUrl, GEOIP_FILE_NAME, GEOIP_ONLY_CN_PRIVATE_FILE_NAME, GEOSITE_FILE_NAME } from '../core/GeoAssets';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { DEFAULT_WEBDAV_BACKUP_DIR, DEFAULT_WEBDAV_BACKUP_FILE_NAME, WebDavConfig, WebDavConfigInput } from '../core/WebDav';
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

  @State private webDavBaseUrl: string = '';
  @State private webDavUsername: string = '';
  @State private webDavPassword: string = '';
  @State private webDavRemotePath: string = DEFAULT_WEBDAV_BACKUP_DIR;
  @State private webDavFileName: string = DEFAULT_WEBDAV_BACKUP_FILE_NAME;
  @State private webDavBusy: boolean = false;

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
              SectionHeader({ title: '内置 Geo 资源', detail: this.t('assets.source.detail') })
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

              SectionHeader({ title: this.t('assets.webdav.title'), detail: this.t('assets.webdav.detail') })
              Column({ space: Space.md }) {
                this.WebDavInputRow(this.t('assets.webdav.url'), this.webDavBaseUrl, 'https://example.com/remote.php/dav/files/user', (value: string) => {
                  this.webDavBaseUrl = value;
                })
                this.WebDavInputRow(this.t('assets.webdav.user'), this.webDavUsername, this.t('assets.webdav.user'), (value: string) => {
                  this.webDavUsername = value;
                })
                this.WebDavInputRow(this.t('assets.webdav.pass'), this.webDavPassword, this.t('assets.webdav.pass'), (value: string) => {
                  this.webDavPassword = value;
                })
                this.WebDavInputRow(this.t('assets.webdav.remotePath'), this.webDavRemotePath, DEFAULT_WEBDAV_BACKUP_DIR, (value: string) => {
                  this.webDavRemotePath = value;
                })
                this.WebDavInputRow(this.t('assets.webdav.fileName'), this.webDavFileName, DEFAULT_WEBDAV_BACKUP_FILE_NAME, (value: string) => {
                  this.webDavFileName = value;
                })

                Row({ space: Space.md }) {
                  this.WebDavButton(this.t('assets.webdav.save'), false, () => this.saveWebDavConfig(true))
                  this.WebDavButton(this.t('assets.webdav.backup'), true, () => this.backupWebDav())
                  this.WebDavButton(this.t('assets.webdav.restore'), false, () => this.restoreWebDav())
                }
                .width('100%')
              }
              .width('100%')
              .padding(Space.lg)
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

  @Builder
  private WebDavInputRow(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: Space.sm }) {
      Text(label)
        .fontSize(FontSz.footnote)
        .fontColor(AppColor.textSecondary)
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .height(42)
        .fontSize(FontSz.body)
        .fontColor(AppColor.textPrimary)
        .placeholderColor(AppColor.textTertiary)
        .backgroundColor(AppColor.surfaceAlt)
        .borderRadius(Radius.md)
        .padding({ left: Space.md, right: Space.md })
        .onChange((next: string) => {
          onChange(next);
        })
    }
    .width('100%')
  }

  @Builder
  private WebDavButton(title: string, primary: boolean, onTap: () => void) {
    Button() {
      Row() {
        if (this.webDavBusy && primary) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(AppColor.onBrand)
            .margin({ right: Space.xs })
        }
        Text(title)
          .fontSize(FontSz.footnote)
          .fontWeight(FontWeight.Medium)
          .fontColor(primary ? AppColor.onBrand : AppColor.textSecondary)
      }
    }
    .layoutWeight(1)
    .height(42)
    .enabled(!this.webDavBusy)
    .backgroundColor(primary ? AppColor.brand : AppColor.surfaceAlt)
    .borderRadius(Radius.pill)
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
      promptAction.showToast({ message: '已有文件在下载中，请稍后' });
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
      promptAction.showToast({ message: `打开文件选择器失败: ${JSON.stringify(error)}` });
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
    this.geositeStatus = ASSETS_CONTROLLER.getFileStatus(context, GEOSITE_FILE_NAME, this.language);
    this.geoipStatus = ASSETS_CONTROLLER.getFileStatus(context, GEOIP_FILE_NAME, this.language);
    this.geoipOnlyCnPrivateStatus = ASSETS_CONTROLLER.getFileStatus(context, GEOIP_ONLY_CN_PRIVATE_FILE_NAME, this.language);
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

  private currentWebDavConfig(): WebDavConfigInput {
    return {
      baseUrl: this.webDavBaseUrl,
      username: this.webDavUsername,
      password: this.webDavPassword,
      remoteBasePath: this.webDavRemotePath,
      remoteFileName: this.webDavFileName
    };
  }

  private applyWebDavConfig(config: WebDavConfig): void {
    this.webDavBaseUrl = config.baseUrl;
    this.webDavUsername = config.username;
    this.webDavPassword = config.password;
    this.webDavRemotePath = config.remoteBasePath;
    this.webDavFileName = config.remoteFileName;
  }

  private async saveWebDavConfig(showToast: boolean): Promise<WebDavConfig> {
    const context = getContext(this) as common.Context;
    const saved = await AssetStore.saveWebDavConfig(context, this.currentWebDavConfig());
    this.applyWebDavConfig(saved);
    if (showToast) {
      promptAction.showToast({ message: this.t('assets.webdav.saved') });
    }
    return saved;
  }

  private async backupWebDav(): Promise<void> {
    if (this.webDavBusy) {
      return;
    }
    const context = getContext(this) as common.Context;
    this.webDavBusy = true;
    try {
      const config = this.currentWebDavConfig();
      await this.saveWebDavConfig(false);
      await ASSETS_CONTROLLER.backupConfigToWebDav(context, this.language, config);
    } finally {
      this.webDavBusy = false;
    }
  }

  private async restoreWebDav(): Promise<void> {
    if (this.webDavBusy) {
      return;
    }
    const context = getContext(this) as common.Context;
    this.webDavBusy = true;
    try {
      const config = this.currentWebDavConfig();
      await this.saveWebDavConfig(false);
      await ASSETS_CONTROLLER.restoreConfigFromWebDav(
        context,
        this.language,
        config,
        () => {
          this.loadState();
          this.loadCustomAssets();
        },
        () => {}
      );
    } finally {
      this.webDavBusy = false;
    }
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

    this.applyWebDavConfig(await AssetStore.loadWebDavConfig(context));
    this.updateFileStatus();
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
