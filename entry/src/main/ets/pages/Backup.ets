import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { ConfigBackup, parseConfigBackup, serializeConfigBackup } from '../core/ConfigBackup';
import { BackupManager } from '../services/BackupManager';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

const MAX_IMPORT_FILE_BYTES: number = 4 * 1024 * 1024; // 备份文件上限 4MB
const PRE_IMPORT_BACKUP_FILE: string = 'pre_import_backup.json';

@Entry
@Component
struct BackupPage {
  @StorageProp('appLanguage') private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private busy: boolean = false;
  @State private subscriptionCount: number = 0;
  @State private nodeCount: number = 0;
  @State private routingCount: number = 0;
  @State private assetCount: number = 0;

  aboutToAppear(): void {
    this.loadSummary();
  }

  private async loadSummary(): Promise<void> {
    try {
      // 读配置统一用 UIContext 宿主 context：getContext(this) 在部分场景拿到的
      // 不是承载 preferences 的那个 context，会静默读到空数据（真机回归）。
      const context = this.getUIContext().getHostContext() as common.Context;
      const backup = await BackupManager.collectBackup(context);
      this.refreshSummary(backup);
    } catch (error) {
      // 概要加载失败不阻断页面，但必须让日志看见，否则会静默显示 0。
      const detail = error instanceof Error ? error.message : JSON.stringify(error);
      SHARED_RUNTIME_CONTROLLER.appendLog(`backup summary failed: ${detail}`);
    }
  }

  build() {
    Column() {
      PageHeader({ title: this.t('backup.title') })
      Scroll() {
        Column({ space: Space.lg }) {
          this.IntroCard()
          this.SummaryCard()
          this.ActionCard(
            this.t('backup.export.button'),
            this.t('backup.export.detail'),
            true,
            () => {
              this.exportBackup();
            }
          )
          this.ActionCard(
            this.t('backup.import.button'),
            this.t('backup.import.detail'),
            false,
            () => {
              this.importBackup();
            }
          )
          Text(this.t('backup.sensitiveWarning'))
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
            .width('100%')
        }
        .width('100%')
        .padding(Space.lg)
        .alignItems(HorizontalAlign.Start)
      }
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private IntroCard() {
    Column() {
      Text(this.t('backup.intro'))
        .fontSize(FontSz.body)
        .fontColor(AppColor.textSecondary)
        .width('100%')
    }
    .width('100%')
    .padding(Space.lg)
    .borderRadius(Radius.lg)
    .backgroundColor(AppColor.surface)
  }

  @Builder
  private SummaryCard() {
    Column({ space: Space.sm }) {
      this.SummaryRow('backup.stat.subscriptions', 'subscriptions')
      this.SummaryRow('backup.stat.nodes', 'nodes')
      this.SummaryRow('backup.stat.routing', 'routing')
      this.SummaryRow('backup.stat.assets', 'assets')
    }
    .width('100%')
    .padding(Space.lg)
    .borderRadius(Radius.lg)
    .backgroundColor(AppColor.surface)
  }

  // 值按 key 取、在 Builder 内部读状态：@Builder 的按值形参在状态变化后会冻结，
  // 直接传 this.xxxCount 会让统计永远显示初始值 0（真机回归）。
  @Builder
  private SummaryRow(labelKey: string, valueKey: string) {
    Row() {
      Text(this.t(labelKey))
        .fontSize(FontSz.body)
        .fontColor(AppColor.textSecondary)
        .layoutWeight(1)
      Text(this.summaryValue(valueKey).toString())
        .fontSize(FontSz.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
    }
    .width('100%')
  }

  @Builder
  private ActionCard(label: string, detail: string, primary: boolean, onTap: () => void) {
    Column({ space: Space.xs }) {
      Text(label)
        .fontSize(FontSz.callout)
        .fontWeight(FontWeight.Medium)
        .fontColor(primary ? AppColor.onBrand : AppColor.textPrimary)
        .width('100%')
      Text(detail)
        .fontSize(FontSz.footnote)
        .fontColor(primary ? AppColor.onBrand : AppColor.textTertiary)
        .width('100%')
    }
    .width('100%')
    .padding(Space.lg)
    .borderRadius(Radius.lg)
    .backgroundColor(primary ? AppColor.brand : AppColor.surface)
    .opacity(this.busy ? 0.6 : 1)
    .onClick(() => {
      if (!this.busy) {
        onTap();
      }
    })
  }

  private async exportBackup(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      // 读配置统一用 UIContext 宿主 context：getContext(this) 在部分场景拿到的
      // 不是承载 preferences 的那个 context，会静默读到空数据（真机回归）。
      const context = this.getUIContext().getHostContext() as common.Context;
      const backup = await BackupManager.collectBackup(context);
      const text = serializeConfigBackup(backup);
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [this.defaultBackupFileName()];
      saveOptions.fileSuffixChoices = ['.json'];
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        return;
      }
      this.writeTextToUri(uris[0], text);
      promptAction.showToast({ message: this.t('backup.export.success') });
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('backup.export.success'));
    } catch (error) {
      promptAction.showToast({ message: this.f1('backup.export.failed', 'error', this.stringifyError(error)) });
    } finally {
      this.busy = false;
    }
  }

  private async importBackup(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.fileSuffixFilters = ['.json'];
      documentSelectOptions.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.select(documentSelectOptions);
      if (!uris || uris.length === 0) {
        return;
      }
      const content = this.readTextFromUri(uris[0]);
      const result = parseConfigBackup(content);
      if (!result.ok || result.backup === null) {
        promptAction.showToast({ message: this.mapParseError(result.error) });
        return;
      }
      this.confirmImport(result.backup);
    } catch (error) {
      promptAction.showToast({ message: this.f1('backup.import.failed', 'error', this.stringifyError(error)) });
    } finally {
      this.busy = false;
    }
  }

  private confirmImport(backup: ConfigBackup): void {
    const detail = this.f1('backup.import.confirmMessage', 'count', this.countNodes(backup).toString());
    AlertDialog.show({
      title: this.t('backup.import.confirmTitle'),
      message: detail,
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: this.t('backup.import.confirm'),
        fontColor: AppColor.onBrand,
        backgroundColor: AppColor.brand,
        action: () => {
          this.applyImport(backup);
        }
      },
      secondaryButton: {
        value: this.t('action.close'),
        fontColor: AppColor.textSecondary,
        backgroundColor: AppColor.bg,
        action: () => {
        }
      }
    });
  }

  private async applyImport(backup: ConfigBackup): Promise<void> {
    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      // 导入前自动留一份当前配置的安全副本，误导入可手动找回。
      try {
        const current = await BackupManager.collectBackup(context);
        this.writeFilesDirFile(context, PRE_IMPORT_BACKUP_FILE, serializeConfigBackup(current));
      } catch (copyError) {
        // 安全副本失败不阻断恢复
      }
      await BackupManager.applyBackup(context, backup);
      this.refreshSummary(backup);
      promptAction.showToast({ message: this.t('backup.import.success') });
      SHARED_RUNTIME_CONTROLLER.appendLog(this.t('backup.import.success'));
    } catch (error) {
      promptAction.showToast({ message: this.f1('backup.import.failed', 'error', this.stringifyError(error)) });
    } finally {
      this.busy = false;
    }
  }

  private summaryValue(key: string): number {
    if (key === 'subscriptions') {
      return this.subscriptionCount;
    }
    if (key === 'nodes') {
      return this.nodeCount;
    }
    if (key === 'routing') {
      return this.routingCount;
    }
    return this.assetCount;
  }

  private refreshSummary(backup: ConfigBackup): void {
    this.subscriptionCount = backup.subscriptions.groups.length;
    this.nodeCount = this.countNodes(backup);
    this.routingCount = backup.settings.routingRules.length;
    this.assetCount = backup.assets.length;
  }

  private countNodes(backup: ConfigBackup): number {
    let nodes = 0;
    for (let i = 0; i < backup.subscriptions.groups.length; i++) {
      nodes += backup.subscriptions.groups[i].nodes.length;
    }
    return nodes;
  }

  private mapParseError(code: string): string {
    if (code === 'empty') {
      return this.t('backup.error.empty');
    }
    if (code === 'invalid-json') {
      return this.t('backup.error.invalidJson');
    }
    if (code === 'invalid-format') {
      return this.t('backup.error.invalidFormat');
    }
    if (code === 'not-hey-backup') {
      return this.t('backup.error.notHeyBackup');
    }
    if (code === 'unsupported-version') {
      return this.t('backup.error.unsupportedVersion');
    }
    return this.t('backup.error.missingFields');
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

  private writeFilesDirFile(context: common.UIAbilityContext, name: string, content: string): void {
    const path = context.filesDir + '/' + name;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
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
            throw new Error(this.t('backup.error.tooLarge'));
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

  private defaultBackupFileName(): string {
    const date = new Date();
    const stamp = `${date.getFullYear()}${this.pad2(date.getMonth() + 1)}${this.pad2(date.getDate())}-${this.pad2(date.getHours())}${this.pad2(date.getMinutes())}${this.pad2(date.getSeconds())}`;
    return `hey-backup-${stamp}.json`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return (error as Error).message;
    }
    return JSON.stringify(error);
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}
