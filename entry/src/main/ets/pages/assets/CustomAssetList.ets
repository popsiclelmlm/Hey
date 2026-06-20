import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { hasDuplicateAssetName, isEditableCustomAssetUrl } from '../../core/AssetUrls';
import { AppLanguage } from '../../core/Profile';
import { translate } from '../../core/I18n';
import { ASSETS_CONTROLLER } from '../../features/assets/AssetsController';
import { AssetStore, CustomAssetUrl } from '../../storage/AssetStore';
import { AssetAddEditDialog } from './AssetAddEditDialog';
import { PageHeader } from '../../shell/PageHeader';
import { AppColor, FontSz, Radius, Space } from '../../theme/Theme';
import { formatOne } from '../../utils/LocalizationPresenter';

@Component
export struct CustomAssetList {
  @Prop language: AppLanguage;
  @Link customAssets: Array<CustomAssetUrl>;
  @Link tempImportUri: string; // 用于从主页面传递过来本地导入的 URI
  @Link tempAssetName: string;
  @Link tempAssetUrl: string;
  onBack: () => void = () => {};

  @State private downloadingFile: string = '';

  // 弹窗状态管理
  @State private showAddEditDialog: boolean = false;
  @State private editId: string = '';
  @State private dialogTitle: string = '';
  @State private initialName: string = '';
  @State private initialUrl: string = '';

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }

  aboutToAppear() {
    this.checkAutoImport();
  }

  // 监听主页面传入的临时资源，自动弹出添加弹窗
  private checkAutoImport() {
    if (this.tempImportUri && this.tempImportUri.length > 0) {
      this.editId = '';
      this.initialName = '';
      this.initialUrl = 'local://import';
      this.dialogTitle = this.t('assets.addUrlTitle');
      this.showAddEditDialog = true;
    } else if (this.tempAssetUrl && this.tempAssetUrl.length > 0) {
      this.editId = '';
      this.initialName = this.tempAssetName;
      this.initialUrl = this.tempAssetUrl;
      this.dialogTitle = this.t('assets.addUrlTitle');
      this.showAddEditDialog = true;
    }
  }

  build() {
    Stack() {
      // 列表主视图
      Column() {
        PageHeader({
          title: this.t('assets.userUrls.title'),
          summary: this.t('assets.userUrls.detail'),
          showBack: true,
          onBack: () => {
            this.onBack();
          }
        })

        List({ space: Space.md }) {
          ForEach(this.customAssets, (item: CustomAssetUrl) => {
            ListItem() {
              this.AssetRow(item)
            }
            .swipeAction({ end: this.RowSwipeActions(item) })
          }, (item: CustomAssetUrl) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.sm })

        // 底部添加按钮
        Column() {
          Button(this.t('assets.addUrlTitle'))
            .width('100%')
            .height(46)
            .backgroundColor(AppColor.brand)
            .fontColor(AppColor.onBrand)
            .fontWeight(FontWeight.Medium)
            .borderRadius(Radius.pill)
            .onClick(() => {
              this.openAddDialog();
            })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.xl })
        .backgroundColor(AppColor.bg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.bg)

      // 添加/编辑弹窗 Overlay
      if (this.showAddEditDialog) {
        AssetAddEditDialog({
          language: this.language,
          title: this.dialogTitle,
          initialName: this.initialName,
          initialUrl: this.initialUrl,
          onCancel: () => {
            this.showAddEditDialog = false;
            this.clearTemporaryImport();
          },
          onConfirm: (name, url) => {
            this.saveCustomAsset(name, url);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private AssetRow(item: CustomAssetUrl) {
    Row({ space: Space.md }) {
      Row() {
        Image($r('app.media.ic_article'))
          .width(20)
          .height(20)
          .fillColor(AppColor.success)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(AppColor.successTint)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 3 }) {
        Text(item.name)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.url.startsWith('local://') ? this.t('assets.localImportedLabel') : item.url)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.getCustomFileStatus(item.name))
          .fontSize(FontSz.caption)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.downloadingFile === item.name) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(AppColor.brand)
      }
    }
    .width('100%')
    .padding(Space.lg)
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .onClick(() => {
      if (isEditableCustomAssetUrl(item.url)) {
        this.openEditDialog(item);
      }
    })
  }

  @Builder
  private RowSwipeActions(item: CustomAssetUrl) {
    Row() {
      if (item.url.startsWith('local://')) {
        this.SwipeButton($r('app.media.ic_folder'), this.t('assets.action.reimportLocal'), AppColor.brand, () => {
          this.reimportLocalCustomAsset(item);
        })
      } else {
        this.SwipeButton($r('app.media.ic_refresh'), this.t('action.update'), AppColor.brand, () => {
          this.downloadCustomAsset(item.name, item.url);
        })
      }
      if (isEditableCustomAssetUrl(item.url)) {
        this.SwipeButton($r('app.media.ic_edit'), this.t('action.edit'), AppColor.textSecondary, () => {
          this.openEditDialog(item);
        })
      }
      this.SwipeButton($r('app.media.ic_delete'), this.t('action.delete'), AppColor.danger, () => {
        this.deleteCustomAsset(item);
      })
    }
    .height('100%')
  }

  @Builder
  private SwipeButton(icon: Resource, label: string, bg: ResourceColor, action: () => void) {
    Column({ space: 3 }) {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(Color.White)
      Text(label)
        .fontSize(FontSz.caption)
        .fontColor(Color.White)
    }
    .width(72)
    .height('100%')
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      action();
    })
  }

  private openAddDialog(): void {
    this.clearTemporaryImport();
    this.editId = '';
    this.initialName = '';
    this.initialUrl = '';
    this.dialogTitle = this.t('assets.addUrlTitle');
    this.showAddEditDialog = true;
  }

  private openEditDialog(item: CustomAssetUrl): void {
    this.editId = item.id;
    this.initialName = item.name;
    this.initialUrl = item.url;
    this.dialogTitle = this.t('assets.editUrlTitle');
    this.showAddEditDialog = true;
  }

  // 获取自定义文件大小
  private getCustomFileStatus(name: string): string {
    const context = getContext(this) as common.Context;
    return ASSETS_CONTROLLER.getCustomFileStatus(context, name, this.language);
  }

  // 网络下载更新
  private async downloadCustomAsset(name: string, url: string): Promise<void> {
    if (this.downloadingFile.length > 0) {
      promptAction.showToast({ message: this.t('assets.downloadBusy') });
      return;
    }
    const context = getContext(this) as common.Context;
    await ASSETS_CONTROLLER.downloadAsset(
      context,
      name,
      url,
      this.language,
      () => { this.downloadingFile = name; },
      () => {},
      () => {},
      () => { this.downloadingFile = ''; }
    );
  }

  // 本地文件覆盖导入
  private async reimportLocalCustomAsset(item: CustomAssetUrl): Promise<void> {
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
      const context = getContext(this) as common.Context;
      await ASSETS_CONTROLLER.copyLocalFileToAssets(
        context,
        fileUri,
        `${item.name}.dat`,
        this.language,
        () => {},
        () => {}
      );
    } catch (error) {
      promptAction.showToast({ message: this.f1('assets.reimportLocalFailed', 'error', JSON.stringify(error)) });
    }
  }

  // 保存（新增/编辑）自定义 URL
  private async saveCustomAsset(name: string, url: string): Promise<void> {
    const trimmedName = name.trim();
    const trimmedUrl = url.trim();

    if (trimmedName.length === 0) {
      promptAction.showToast({ message: this.t('assets.urlNameEmpty') });
      return;
    }

    if (hasDuplicateAssetName(this.customAssets, trimmedName, this.editId)) {
      promptAction.showToast({ message: this.t('assets.urlNameDuplicate') });
      return;
    }

    const isLocalImport = trimmedUrl.startsWith('local://');
    if (!isLocalImport && !trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://')) {
      promptAction.showToast({ message: this.t('assets.urlAddressInvalid') });
      return;
    }

    const context = getContext(this) as common.Context;

    // 如果是本地导入且有临时导入的 URI，先执行文件拷贝
    if (isLocalImport && this.tempImportUri.length > 0) {
      const copySuccess = await ASSETS_CONTROLLER.copyLocalFileToAssets(
        context,
        this.tempImportUri,
        `${trimmedName}.dat`,
        this.language,
        () => {},
        () => {}
      );
      if (!copySuccess) {
        return; // 拷贝失败，不保存
      }
      this.tempImportUri = '';
    }
    this.tempAssetName = '';
    this.tempAssetUrl = '';

    if (this.editId.length > 0) {
      this.customAssets = this.customAssets.map(item => {
        if (item.id === this.editId) {
          return { id: item.id, name: trimmedName, url: trimmedUrl };
        }
        return item;
      });
    } else {
      const newItem: CustomAssetUrl = {
        id: Date.now().toString(),
        name: trimmedName,
        url: trimmedUrl
      };
      this.customAssets.push(newItem);
    }

    await AssetStore.save(context, this.customAssets);
    this.showAddEditDialog = false;
    this.clearTemporaryImport();
    promptAction.showToast({ message: this.t('assets.saveSuccess') });
  }

  private clearTemporaryImport(): void {
    this.tempImportUri = '';
    this.tempAssetName = '';
    this.tempAssetUrl = '';
  }

  // 删除自定义 URL
  private async deleteCustomAsset(item: CustomAssetUrl): Promise<void> {
    const context = getContext(this) as common.Context;
    this.customAssets = await ASSETS_CONTROLLER.deleteCustomAsset(context, item, this.customAssets, this.language);
  }
}
