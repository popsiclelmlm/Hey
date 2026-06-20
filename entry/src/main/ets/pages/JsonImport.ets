import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { resolveJsonConfigNodeName } from '../core/JsonConfigNames';
import { AppLanguage, ProxyNode, XrayConfigType } from '../core/Profile';
import { markRuntimeSettingsRestartNeeded } from '../core/SettingsChange';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { ensureReadPasteboardPermission } from '../utils/ClipboardPermission';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

const MAX_IMPORT_FILE_BYTES: number = 2 * 1024 * 1024;

interface JsonImportParams {
  nodeId?: string;
}

@Entry
@Component
struct JsonImportPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private nodeName: string = '';
  @State private outboundJson: string = '';
  @State private validationMessage: string = '';
  @State private validationOk: boolean = false;
  @State private editMode: boolean = false;
  @State private isBusy: boolean = false;
  @State private lastError: string = '';
  private editNodeId: string = '';
  private editConfigType: XrayConfigType | undefined = undefined;
  private stateLoaded: boolean = false;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.editMode ? this.t('jsonImport.editTitle') : this.t('screen.jsonImport.title'),
        showBack: true
      })

      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: Space.lg }) {
            // 输入卡片
            SectionHeader({ title: this.t('jsonImport.sectionTitle') })
            Column() {
              if (this.editMode) {
                Column({ space: Space.sm }) {
                  Text(this.t('jsonImport.name'))
                    .fontSize(FontSz.footnote)
                    .fontColor(AppColor.textSecondary)
                    .width('100%')
                  TextInput({ text: this.nodeName, placeholder: this.t('jsonImport.namePlaceholder') })
                    .height(44)
                    .fontSize(FontSz.body)
                    .fontColor(AppColor.textPrimary)
                    .placeholderColor(AppColor.textTertiary)
                    .backgroundColor(AppColor.surfaceAlt)
                    .borderRadius(Radius.md)
                    .padding({ left: Space.md, right: Space.md })
                    .onChange((value: string) => {
                      this.nodeName = value;
                    })
                }
                .width('100%')
                .padding({ left: Space.lg, right: Space.lg, top: Space.md })
              }

              // 粘贴 / 清空 操作行
              Row({ space: Space.sm }) {
                Blank()
                Button(this.t('action.paste'))
                  .fontSize(FontSz.footnote)
                  .fontColor(AppColor.brand)
                  .backgroundColor(AppColor.brandTint)
                  .height(30)
                  .padding({ left: Space.md, right: Space.md })
                  .borderRadius(Radius.sm)
                  .onClick(() => {
                    this.pasteFromClipboard();
                  })

                Button(this.t('jsonImport.chooseFile'))
                  .fontSize(FontSz.footnote)
                  .fontColor(AppColor.brand)
                  .backgroundColor(AppColor.brandTint)
                  .height(30)
                  .padding({ left: Space.md, right: Space.md })
                  .borderRadius(Radius.sm)
                  .enabled(!this.isBusy)
                  .onClick(() => {
                    this.pickConfigFile();
                  })

                if (this.outboundJson.length > 0) {
                  Button(this.t('action.clear'))
                    .fontSize(FontSz.footnote)
                    .fontColor(AppColor.danger)
                    .backgroundColor(AppColor.dangerTint)
                    .height(30)
                    .padding({ left: Space.md, right: Space.md })
                    .borderRadius(Radius.sm)
                    .onClick(() => {
                      this.outboundJson = '';
                      this.validateConfig();
                    })
                }
              }
              .width('100%')
              .padding({ left: Space.lg, right: Space.lg, top: Space.md })

              TextArea({
                placeholder: this.t('jsonImport.placeholder'),
                text: this.outboundJson
              })
                .height(260)
                .width('100%')
                .fontSize(FontSz.body)
                .fontColor(AppColor.textPrimary)
                .fontFamily('monospace')
                .backgroundColor(Color.Transparent)
                .borderRadius(0)
                .padding(Space.lg)
                .onChange((value: string) => {
                  this.outboundJson = value;
                  this.validateConfig();
                })
            }
            .width('100%')
            .backgroundColor(AppColor.surface)
            .borderRadius(Radius.lg)
            .clip(true)
            .margin({ left: Space.lg, right: Space.lg })

            Text(this.t('jsonImport.note'))
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.textTertiary)
              .width('100%')
              .lineHeight(16)
              .padding({ left: Space.lg + Space.xs, right: Space.lg + Space.xs })

            // 校验结果指示板
            if (this.outboundJson.trim().length > 0) {
              Column({ space: Space.sm }) {
                Row({ space: Space.sm }) {
                  Column()
                    .width(6)
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(this.validationOk ? AppColor.success : AppColor.danger)

                  Text(this.validationOk ? this.t('jsonImport.valid') : this.t('jsonImport.invalid'))
                    .fontSize(FontSz.body)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.validationOk ? AppColor.success : AppColor.danger)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Text(this.validationMessage)
                  .fontSize(FontSz.footnote)
                  .fontColor(this.validationOk ? AppColor.success : AppColor.danger)
                  .width('100%')
                  .lineHeight(16)
              }
              .width('100%')
              .padding(Space.lg)
              .backgroundColor(this.validationOk ? AppColor.successTint : AppColor.dangerTint)
              .borderRadius(Radius.md)
              .margin({ left: Space.lg, right: Space.lg })
            }

            if (this.lastError.length > 0) {
              Text(this.lastError)
                .fontSize(FontSz.footnote)
                .fontColor(AppColor.danger)
                .width('100%')
                .padding(Space.md)
                .backgroundColor(AppColor.dangerTint)
                .borderRadius(Radius.md)
                .margin({ left: Space.lg, right: Space.lg })
            }
          }
          .width('100%')
          .padding({ top: Space.sm, bottom: 100 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)

        // 底部保存按钮
        Column() {
          Button() {
            Row() {
              if (this.isBusy) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColor.onBrand)
                  .margin({ right: Space.sm })
              }
              Text(this.saveButtonText())
                .fontSize(FontSz.headline)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isSaveEnabled() ? AppColor.onBrand : AppColor.textTertiary)
            }
          }
          .width('100%')
          .height(48)
          .borderRadius(Radius.pill)
          .enabled(this.isSaveEnabled())
          .backgroundColor(this.isSaveEnabled() ? AppColor.brand : AppColor.surfaceAlt)
          .onClick(() => {
            this.saveJsonNode();
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.xxl })
        .backgroundColor(AppColor.bg)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  private isSaveEnabled(): boolean {
    return this.outboundJson.trim().length > 0 &&
      this.validationOk &&
      !this.isBusy &&
      (!this.editMode || this.nodeName.trim().length > 0);
  }

  private async loadState(): Promise<void> {
    if (this.stateLoaded) {
      return;
    }
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    const params = router.getParams() as JsonImportParams;
    if (params !== undefined && params.nodeId !== undefined && params.nodeId.length > 0) {
      this.editMode = true;
      this.editNodeId = params.nodeId;
      const state = await NODES_CONTROLLER.load(context, this.language);
      const node = NODES_CONTROLLER.findNode(state.nodes, this.editNodeId);
      if (node === null) {
        this.lastError = this.t('jsonImport.editMissing');
      } else if (!this.isEditableJsonNode(node)) {
        this.lastError = this.t('jsonImport.editUnsupported');
      } else {
        this.nodeName = node.name;
        this.outboundJson = node.outboundJson;
        this.editConfigType = node.configType ?? 'full';
      }
    }
    this.validateConfig();
    this.stateLoaded = true;
  }

  private validateConfig(): void {
    const value = this.outboundJson.trim();
    if (value.length === 0) {
      this.validationOk = false;
      this.validationMessage = '';
      return;
    }
    const validation = NODES_CONTROLLER.validateConfig(value, this.language, this.editMode ? this.editConfigType : undefined);
    this.validationOk = validation.valid;
    this.validationMessage = validation.message;
  }

  private async saveJsonNode(): Promise<void> {
    if (this.editMode) {
      await this.updateJsonNode();
      return;
    }
    await this.importJsonNode();
  }

  private async importJsonNode(): Promise<void> {
    const value = this.outboundJson.trim();
    if (value.length === 0 || !this.validationOk) {
      return;
    }

    this.isBusy = true;
    try {
      const context = getContext(this) as common.Context;
      const validation = NODES_CONTROLLER.validateConfig(value, this.language);
      if (!validation.valid) {
        this.lastError = validation.message;
        return;
      }

      const normalizedJson = validation.normalizedJson;
      const nodeName = resolveJsonConfigNodeName(normalizedJson, validation.configType);

      const savedProfile = await NODES_CONTROLLER.saveProfile(context, normalizedJson, this.language, validation.configType);
      if (savedProfile.profile === null) {
        this.lastError = savedProfile.lastError;
        return;
      }

      await SubscriptionStore.addManualNode(context, nodeName, normalizedJson, validation.configType);
      markRuntimeSettingsRestartNeeded();
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('jsonImport.imported'));
      promptAction.showToast({ message: this.t('jsonImport.imported') });
      router.back();
    } catch (error) {
      this.lastError = this.f1('jsonImport.importFailed', 'error', this.stringifyError(error));
    } finally {
      this.isBusy = false;
    }
  }

  private async updateJsonNode(): Promise<void> {
    const value = this.outboundJson.trim();
    if (value.length === 0 || !this.validationOk || this.editNodeId.length === 0) {
      return;
    }

    this.isBusy = true;
    try {
      const context = getContext(this) as common.Context;
      const validation = NODES_CONTROLLER.validateConfig(value, this.language, this.editConfigType);
      if (!validation.valid) {
        this.lastError = validation.message;
        return;
      }
      const result = await NODES_CONTROLLER.updateManualNode(
        context,
        this.editNodeId,
        this.nodeName,
        validation.normalizedJson,
        this.language,
        validation.configType
      );
      if (!result.success) {
        this.lastError = result.lastError;
        return;
      }
      if (result.selected) {
        markRuntimeSettingsRestartNeeded();
      }
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('jsonImport.updated'));
      promptAction.showToast({ message: this.t('jsonImport.updated') });
      router.back();
    } catch (error) {
      this.lastError = this.f1('jsonImport.saveFailed', 'error', this.stringifyError(error));
    } finally {
      this.isBusy = false;
    }
  }

  private async pasteFromClipboard() {
    try {
      const context = getContext(this) as common.Context;
      if (!await ensureReadPasteboardPermission(context)) {
        promptAction.showToast({ message: this.t('prompt.clipboardReadFailed') });
        return;
      }
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (systemPasteboard.hasDataSync()) {
        const pasteData = await systemPasteboard.getData();
        const text = pasteData.getPrimaryText();
        if (text && text.trim().length > 0) {
          this.outboundJson = text.trim();
          this.validateConfig();
          promptAction.showToast({ message: this.t('prompt.pastedJsonConfig') });
        } else {
          promptAction.showToast({ message: this.t('prompt.clipboardTextEmpty') });
        }
      } else {
        promptAction.showToast({ message: this.t('prompt.clipboardNoData') });
      }
    } catch (error) {
      promptAction.showToast({ message: this.t('prompt.clipboardReadFailed') });
    }
  }

  private async pickConfigFile(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.fileSuffixFilters = ['.json', '.txt', '.conf'];
      documentSelectOptions.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.select(documentSelectOptions);
      if (!uris || uris.length === 0) {
        return;
      }

      const content = this.readTextFromUri(uris[0]);
      if (content.trim().length === 0) {
        this.lastError = this.t('jsonImport.fileEmpty');
        return;
      }
      this.outboundJson = content.trim();
      this.lastError = '';
      this.validateConfig();
      promptAction.showToast({ message: this.t('jsonImport.fileLoaded') });
    } catch (error) {
      this.lastError = this.f1('jsonImport.fileReadFailed', 'error', this.stringifyError(error));
    }
  }

  private readTextFromUri(uri: string): string {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const decoder = util.TextDecoder.create('utf-8');
      const chunks = new Array<string>();
      let totalBytes = 0;
      let readLength = 0;
      do {
        const buffer = new ArrayBuffer(8192);
        readLength = fs.readSync(file.fd, buffer);
        if (readLength > 0) {
          totalBytes += readLength;
          if (totalBytes > MAX_IMPORT_FILE_BYTES) {
            throw new Error(this.t('jsonImport.fileTooLarge'));
          }
          chunks.push(decoder.decode(new Uint8Array(buffer, 0, readLength)));
        }
      } while (readLength > 0);
      return chunks.join('');
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  private isEditableJsonNode(node: ProxyNode): boolean {
    return node.sourceUrl.trim().length === 0 &&
      node.rawLink.trim().length === 0 &&
      ((node.configType ?? 'outbound') === 'full' || node.protocol === 'custom');
  }

  private saveButtonText(): string {
    return this.editMode ? this.t('jsonImport.saveEdit') : this.t('jsonImport.importButton');
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }

  private stringifyError(error: Object): string {
    const text = `${error}`;
    if (text.length > 0 && text !== '[object Object]') {
      return text;
    }
    return JSON.stringify(error);
  }
}
