import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, ProxyNode } from '../core/Profile';
import { buildNodeExportModel, NodeExportModel } from '../features/nodes/NodeOperations';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

@Entry
@Component
struct ExportPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private nodes: Array<ProxyNode> = [];
  @State private exportTitle: string = '';
  @State private exportContent: string = '';
  @State private exportCount: number = 0;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('export.title'),
        summary: this.f1('export.summary', 'count', this.exportCount.toString()),
        showBack: true
      })
      Scroll() {
        Column({ space: Space.lg }) {
          SectionHeader({ title: this.exportTitle })
          Column() {
            TextArea({
              placeholder: this.t('export.empty'),
              text: this.exportContent
            })
              .height(420)
              .width('100%')
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.textPrimary)
              .fontFamily('monospace')
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding(Space.lg)
              .onChange((value: string) => {
                this.exportContent = value;
              })
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          Text(this.t('export.copyHint'))
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
            .width('100%')
            .padding({ left: Space.lg + Space.xs, right: Space.lg + Space.xs })

          Row({ space: Space.md }) {
            Button(this.t('export.copyAction'))
              .height(44)
              .layoutWeight(1)
              .enabled(this.hasExportContent())
              .backgroundColor(this.hasExportContent() ? AppColor.surfaceAlt : AppColor.border)
              .fontColor(this.hasExportContent() ? AppColor.textPrimary : AppColor.textTertiary)
              .borderRadius(Radius.pill)
              .onClick(() => {
                this.copyExportContent();
              })

            Button(this.t('export.fileAction'))
              .height(44)
              .layoutWeight(1)
              .enabled(this.hasExportContent())
              .backgroundColor(this.hasExportContent() ? AppColor.brand : AppColor.border)
              .fontColor(this.hasExportContent() ? AppColor.onBrand : AppColor.textTertiary)
              .borderRadius(Radius.pill)
              .onClick(() => {
                this.saveExportFile();
              })
          }
          .width('100%')
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
  }

  private async loadState(): Promise<void> {
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    this.nodes = (await NODES_CONTROLLER.load(context, this.language)).nodes;
    const model: NodeExportModel = buildNodeExportModel(this.t('export.nodesTitle'), this.nodes);
    this.exportTitle = model.title;
    this.exportContent = model.content;
    this.exportCount = model.count;
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.exportPrepared', 'count', this.exportCount.toString()));
  }

  private hasExportContent(): boolean {
    return this.exportContent.trim().length > 0;
  }

  private copyExportContent(): void {
    if (!this.hasExportContent()) {
      promptAction.showToast({ message: this.t('export.empty') });
      return;
    }

    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.exportContent.trim());
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setDataSync(pasteData);
      promptAction.showToast({ message: this.t('prompt.copiedToClipboard') });
      SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.exportPrepared', 'count', this.exportCount.toString()));
    } catch (error) {
      promptAction.showToast({ message: '导出剪贴板失败：' + JSON.stringify(error) });
    }
  }

  private async saveExportFile(): Promise<void> {
    if (!this.hasExportContent()) {
      promptAction.showToast({ message: this.t('export.empty') });
      return;
    }

    try {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [this.defaultExportFileName()];
      saveOptions.fileSuffixChoices = ['.txt'];
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        return;
      }
      this.writeTextToUri(uris[0], this.exportContent.trim() + '\n');
      promptAction.showToast({ message: this.t('export.fileSuccess') });
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('export.fileSuccess'));
    } catch (error) {
      promptAction.showToast({ message: this.f1('export.fileFailed', 'error', JSON.stringify(error)) });
    }
  }

  private writeTextToUri(uri: string, content: string): void {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  private defaultExportFileName(): string {
    const date = new Date();
    const stamp = `${date.getFullYear()}${this.pad2(date.getMonth() + 1)}${this.pad2(date.getDate())}-${this.pad2(date.getHours())}${this.pad2(date.getMinutes())}${this.pad2(date.getSeconds())}`;
    return `hey-nodes-${stamp}.txt`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
