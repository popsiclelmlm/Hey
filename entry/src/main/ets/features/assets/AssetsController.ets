import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { AppLanguage } from '../../core/Profile';
import { translate } from '../../core/I18n';
import { buildAppBackupPayload, buildAppBackupZipFromPayload, parseAppBackupData } from '../../core/AppBackup';
import { formatGeoCountSummary, formatGeoCountUnavailable, geoDataSpecForFile, parseGeoCountData } from '../../core/GeoAssets';
import { validateWebDavConfig, WebDavConfigInput } from '../../core/WebDav';
import { countNativeGeoData } from '../../native/HeyNative';
import { formatOne, formatTwo } from '../../utils/LocalizationPresenter';
import { SHARED_RUNTIME_CONTROLLER } from '../runtime/RuntimeController';
import { AssetStore, CustomAssetUrl } from '../../storage/AssetStore';
import { WEBDAV_MANAGER } from '../../services/WebDavManager';

export interface GeoSource {
  name: string;
  url: string;
}

export const GEO_SOURCES: Array<GeoSource> = [
  { name: 'Loyalsoldier (GitHub)', url: 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/' },
  { name: 'Loyalsoldier (JsDelivr)', url: 'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/' }
];

export class AssetsController {
  
  private pad(val: number): string {
    return val < 10 ? `0${val}` : `${val}`;
  }

  private t(language: AppLanguage, key: string): string {
    return translate(language, key);
  }

  // 获取本地 dat 文件大小和修改日期
  getFileStatus(context: common.Context, fileName: string, language: AppLanguage): string {
    const path = `${context.filesDir}/${fileName}`;
    try {
      if (fs.accessSync(path)) {
        const stat = fs.statSync(path);
        const sizeMb = (stat.size / (1024 * 1024)).toFixed(2);
        const date = new Date(stat.mtime * 1000);
        const timeStr = `${date.getFullYear()}/${this.pad(date.getMonth() + 1)}/${this.pad(date.getDate())} ${this.pad(date.getHours())}:${this.pad(date.getMinutes())}:${this.pad(date.getSeconds())}`;
        const status = formatTwo(language, 'assets.fileStatus', 'size', sizeMb, 'time', timeStr);
        const countStatus = this.getGeoCountStatus(context, fileName, stat.mtime, language);
        return countStatus.length > 0 ? `${status} / ${countStatus}` : status;
      }
    } catch (e) {}
    return this.t(language, 'assets.notDownloaded');
  }

  private getGeoCountStatus(context: common.Context, fileName: string, datMtime: number, language: AppLanguage): string {
    const spec = geoDataSpecForFile(fileName);
    if (spec === null) {
      return '';
    }

    const jsonPath = `${context.filesDir}/${spec.name}.json`;
    if (this.shouldRefreshGeoCount(jsonPath, datMtime)) {
      const result = countNativeGeoData(context.filesDir, spec.name, spec.geoType);
      if (!result.ok) {
        return formatGeoCountUnavailable(language, this.compactNativeError(result.message));
      }
    }

    try {
      if (!fs.accessSync(jsonPath)) {
        return '';
      }
      const count = parseGeoCountData(fs.readTextSync(jsonPath));
      return count === null ? '' : formatGeoCountSummary(language, count);
    } catch (error) {
      return '';
    }
  }

  private shouldRefreshGeoCount(jsonPath: string, datMtime: number): boolean {
    try {
      if (!fs.accessSync(jsonPath)) {
        return true;
      }
      const stat = fs.statSync(jsonPath);
      return stat.mtime < datMtime;
    } catch (error) {
      return true;
    }
  }

  private compactNativeError(message: string): string {
    if (message.indexOf('CGoCountGeoData not exported') >= 0) {
      return 'CGoCountGeoData not exported';
    }
    if (message.length > 72) {
      return `${message.substring(0, 69)}...`;
    }
    return message;
  }

  // 获取自定义资源的大小
  getCustomFileStatus(context: common.Context, name: string, language: AppLanguage): string {
    const path = `${context.filesDir}/${name}.dat`;
    try {
      if (fs.accessSync(path)) {
        const stat = fs.statSync(path);
        const sizeMb = (stat.size / (1024 * 1024)).toFixed(2);
        return `${sizeMb} MB`;
      }
    } catch (e) {}
    return this.t(language, 'assets.notDownloaded');
  }

  // 执行资源网络更新下载
  async downloadAsset(
    context: common.Context,
    fileName: string,
    url: string,
    language: AppLanguage,
    onStart: () => void,
    onSuccess: () => void,
    onError: (errMsg: string) => void,
    onComplete: () => void
  ): Promise<void> {
    onStart();

    const tempPath = `${context.filesDir}/${fileName}.tmp`;
    const targetPath = `${context.filesDir}/${fileName.endsWith('.dat') ? fileName : fileName + '.dat'}`;

    const request = http.createHttp();
    try {
      promptAction.showToast({ message: this.t(language, 'assets.downloading').replace('{title}', fileName) });
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 60000,
        connectTimeout: 15000,
        usingCache: false
      });

      if (response.responseCode === 200) {
        const file = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, response.result as ArrayBuffer);
        fs.closeSync(file);

        try {
          if (fs.accessSync(targetPath)) {
            fs.unlinkSync(targetPath);
          }
        } catch (e) {}

        fs.renameSync(tempPath, targetPath);
        promptAction.showToast({ message: this.t(language, 'assets.downloadSuccess').replace('{title}', fileName) });
        onSuccess();
      } else {
        throw new Error(`HTTP ${response.responseCode}`);
      }
    } catch (error) {
      try {
        if (fs.accessSync(tempPath)) {
          fs.unlinkSync(tempPath);
        }
      } catch (e) {}

      const errMsg = error instanceof Error ? error.message : JSON.stringify(error);
      promptAction.showToast({
        message: this.t(language, 'assets.downloadFailed')
          .replace('{title}', fileName)
          .replace('{error}', errMsg)
      });
      onError(errMsg);
    } finally {
      request.destroy();
      onComplete();
    }
  }

  // 顺序一键更新全部 Geo 资源
  async downloadAllAssets(
    context: common.Context,
    currentSourceUrl: string,
    language: AppLanguage,
    onProgress: (fileName: string) => void,
    onComplete: (successGeosite: boolean, successGeoip: boolean) => void
  ): Promise<void> {
    try {
      promptAction.showToast({ message: this.t(language, 'assets.updatingAll') });

      // 下载 geosite.dat
      onProgress('geosite.dat');
      const successGeosite = await this.performDownload(context, 'geosite.dat', `${currentSourceUrl}geosite.dat`);

      // 下载 geoip.dat
      onProgress('geoip.dat');
      const successGeoip = await this.performDownload(context, 'geoip.dat', `${currentSourceUrl}geoip.dat`);

      if (successGeosite && successGeoip) {
        promptAction.showToast({ message: this.t(language, 'assets.updateAllSuccess') });
      } else if (successGeosite || successGeoip) {
        promptAction.showToast({ message: '部分规则文件更新成功，部分失败。' });
      } else {
        promptAction.showToast({ message: '一键更新失败，请检查网络或更换下载源。' });
      }
      onComplete(successGeosite, successGeoip);
    } catch (error) {
      promptAction.showToast({ message: `一键更新出错: ${JSON.stringify(error)}` });
      onComplete(false, false);
    }
  }

  private async performDownload(context: common.Context, fileName: string, url: string): Promise<boolean> {
    const tempPath = `${context.filesDir}/${fileName}.tmp`;
    const targetPath = `${context.filesDir}/${fileName}`;
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 60000,
        connectTimeout: 15000,
        usingCache: false
      });
      if (response.responseCode === 200) {
        const file = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, response.result as ArrayBuffer);
        fs.closeSync(file);
        try {
          if (fs.accessSync(targetPath)) {
            fs.unlinkSync(targetPath);
          }
        } catch (e) {}
        fs.renameSync(tempPath, targetPath);
        return true;
      }
    } catch (error) {
      try {
        if (fs.accessSync(tempPath)) {
          fs.unlinkSync(tempPath);
        }
      } catch (e) {}
    } finally {
      request.destroy();
    }
    return false;
  }

  // 流式拷贝文件到沙箱
  async copyLocalFileToAssets(
    context: common.Context,
    srcUri: string,
    destFileName: string,
    language: AppLanguage,
    onSuccess: () => void,
    onError: (errMsg: string) => void
  ): Promise<boolean> {
    const destPath = `${context.filesDir}/${destFileName}`;
    const tempPath = `${context.filesDir}/${destFileName}.tmp`;

    let srcFile: fs.File | null = null;
    let destFile: fs.File | null = null;
    try {
      srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      destFile = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

      const buf = new ArrayBuffer(8192);
      let readLen = 0;
      while ((readLen = fs.readSync(srcFile.fd, buf)) > 0) {
        fs.writeSync(destFile.fd, buf, { length: readLen });
      }

      fs.closeSync(srcFile);
      fs.closeSync(destFile);
      srcFile = null;
      destFile = null;

      try {
        if (fs.accessSync(destPath)) {
          fs.unlinkSync(destPath);
        }
      } catch (e) {}
      fs.renameSync(tempPath, destPath);

      promptAction.showToast({ message: this.t(language, 'assets.action.importLocal.success').replace('{title}', destFileName) });
      onSuccess();
      return true;
    } catch (error) {
      if (srcFile) fs.closeSync(srcFile);
      if (destFile) fs.closeSync(destFile);
      try {
        if (fs.accessSync(tempPath)) {
          fs.unlinkSync(tempPath);
        }
      } catch (e) {}

      const errMsg = error instanceof Error ? error.message : JSON.stringify(error);
      promptAction.showToast({ message: this.t(language, 'assets.action.importLocal.failed').replace('{error}', errMsg) });
      onError(errMsg);
      return false;
    }
  }

  // 删除 Geo 资源
  deleteAsset(context: common.Context, fileName: string, language: AppLanguage, onComplete: () => void): void {
    const targetPath = `${context.filesDir}/${fileName}`;
    try {
      if (fs.accessSync(targetPath)) {
        fs.unlinkSync(targetPath);
        promptAction.showToast({ message: this.t(language, 'assets.deleteSuccess').replace('{title}', fileName) });
      }
    } catch (error) {
      promptAction.showToast({ message: `删除失败: ${JSON.stringify(error)}` });
    } finally {
      onComplete();
    }
  }

  // 删除自定义 URL 链接及本地 dat 文件
  async deleteCustomAsset(context: common.Context, item: CustomAssetUrl, customAssets: Array<CustomAssetUrl>): Promise<Array<CustomAssetUrl>> {
    const path = `${context.filesDir}/${item.name}.dat`;
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {}

    const updated = customAssets.filter(asset => asset.id !== item.id);
    await AssetStore.save(context, updated);
    promptAction.showToast({ message: '已删除自定义链接及本地缓存' });
    return updated;
  }

  // 配置一键备份到剪贴板
  async backupConfig(context: common.Context, language: AppLanguage): Promise<void> {
    try {
      const backupStr = await this.buildBackupText(context);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, backupStr);
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: this.t(language, 'assets.backupSuccess') });
      SHARED_RUNTIME_CONTROLLER.appendLog('已完成应用配置备份并复制到剪贴板。');
    } catch (error) {
      promptAction.showToast({ message: this.t(language, 'assets.backupFailed').replace('{error}', JSON.stringify(error)) });
    }
  }

  // 配置从剪贴板一键还原
  async restoreConfig(
    context: common.Context,
    language: AppLanguage,
    onSuccess: () => void,
    onFailure: () => void
  ): Promise<void> {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (!systemPasteboard.hasDataSync()) {
        promptAction.showToast({ message: this.t(language, 'prompt.clipboardEmpty') });
        onFailure();
        return;
      }
      const pasteData = await systemPasteboard.getData();
      const text = pasteData.getPrimaryText();
      if (!text || text.trim().length === 0) {
        promptAction.showToast({ message: this.t(language, 'prompt.clipboardEmpty') });
        onFailure();
        return;
      }

      const restored = await this.applyBackupText(context, text);
      if (!restored) {
        promptAction.showToast({ message: this.t(language, 'assets.invalidBackupData') });
        onFailure();
        return;
      }

      promptAction.showToast({ message: this.t(language, 'assets.restoreSuccess') });
      SHARED_RUNTIME_CONTROLLER.appendLog('应用配置已成功还原。');
      onSuccess();
    } catch (error) {
      promptAction.showToast({ message: this.t(language, 'assets.restoreFailed').replace('{error}', JSON.stringify(error)) });
      onFailure();
    }
  }

  async backupConfigToWebDav(context: common.Context, language: AppLanguage, config: WebDavConfigInput): Promise<boolean> {
    const validation = validateWebDavConfig(config);
    if (!validation.valid) {
      promptAction.showToast({ message: this.localizeWebDavValidationMessage(language, validation.message) });
      return false;
    }

    try {
      promptAction.showToast({ message: this.t(language, 'assets.webdav.backup.start') });
      const backupStr = await this.buildBackupText(context);
      const result = await WEBDAV_MANAGER.uploadData(validation.config, buildAppBackupZipFromPayload(backupStr), 'application/zip');
      if (!result.ok) {
        promptAction.showToast({ message: this.t(language, 'assets.webdav.backup.failed').replace('{error}', result.message) });
        SHARED_RUNTIME_CONTROLLER.appendLog(`WebDAV 备份失败：${result.message}`);
        return false;
      }
      promptAction.showToast({ message: this.t(language, 'assets.webdav.backup.success') });
      SHARED_RUNTIME_CONTROLLER.appendLog(`WebDAV 备份已上传：${result.remoteUrl}`);
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      promptAction.showToast({ message: this.t(language, 'assets.webdav.backup.failed').replace('{error}', message) });
      return false;
    }
  }

  async restoreConfigFromWebDav(
    context: common.Context,
    language: AppLanguage,
    config: WebDavConfigInput,
    onSuccess: () => void,
    onFailure: () => void
  ): Promise<void> {
    const validation = validateWebDavConfig(config);
    if (!validation.valid) {
      promptAction.showToast({ message: this.localizeWebDavValidationMessage(language, validation.message) });
      onFailure();
      return;
    }

    try {
      promptAction.showToast({ message: this.t(language, 'assets.webdav.restore.start') });
      const result = await WEBDAV_MANAGER.downloadData(validation.config);
      if (!result.ok) {
        promptAction.showToast({ message: this.t(language, 'assets.webdav.restore.failed').replace('{error}', result.message) });
        SHARED_RUNTIME_CONTROLLER.appendLog(`WebDAV 还原下载失败：${result.message}`);
        onFailure();
        return;
      }
      if (result.data === null) {
        promptAction.showToast({ message: this.t(language, 'assets.invalidBackupData') });
        onFailure();
        return;
      }
      const restored = await this.applyBackupData(context, result.data);
      if (!restored) {
        promptAction.showToast({ message: this.t(language, 'assets.invalidBackupData') });
        onFailure();
        return;
      }
      promptAction.showToast({ message: this.t(language, 'assets.webdav.restore.success') });
      SHARED_RUNTIME_CONTROLLER.appendLog(`WebDAV 备份已还原：${result.remoteUrl}`);
      onSuccess();
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      promptAction.showToast({ message: this.t(language, 'assets.webdav.restore.failed').replace('{error}', message) });
      onFailure();
    }
  }

  private async buildBackupText(context: common.Context): Promise<string> {
    const profileStore = await preferences.getPreferences(context, 'hey_vpn_profile');
    const settingsStore = await preferences.getPreferences(context, 'hey_vpn_settings');
    const subStore = await preferences.getPreferences(context, 'hey_vpn_subscription');
    const assetStore = await preferences.getPreferences(context, 'hey_vpn_assets');

    const profileVal = await profileStore.get('default_profile', '');
    const settingsVal = await settingsStore.get('app_settings', '');
    const subVal = await subStore.get('subscription_profile', '');
    const assetVal = await assetStore.get('custom_assets', '');

    return buildAppBackupPayload(
      profileVal.toString(),
      settingsVal.toString(),
      subVal.toString(),
      assetVal.toString()
    );
  }

  private async applyBackupText(context: common.Context, backupText: string): Promise<boolean> {
    return this.applyBackupData(context, backupText);
  }

  private async applyBackupData(context: common.Context, backupData: string | ArrayBuffer): Promise<boolean> {
    const parsed = parseAppBackupData(backupData);
    if (!parsed.valid || parsed.payload === null) {
      return false;
    }
    const payload = parsed.payload;
    const profileStore = await preferences.getPreferences(context, 'hey_vpn_profile');
    const settingsStore = await preferences.getPreferences(context, 'hey_vpn_settings');
    const subStore = await preferences.getPreferences(context, 'hey_vpn_subscription');
    const assetStore = await preferences.getPreferences(context, 'hey_vpn_assets');

    await profileStore.put('default_profile', payload.profile);
    await profileStore.flush();
    await settingsStore.put('app_settings', payload.settings);
    await settingsStore.flush();
    await subStore.put('subscription_profile', payload.subscription);
    await subStore.flush();
    await assetStore.put('custom_assets', payload.assets);
    await assetStore.flush();
    return true;
  }

  private localizeWebDavValidationMessage(language: AppLanguage, message: string): string {
    if (message === 'WebDAV 服务器地址必须以 http:// 或 https:// 开头。') {
      return this.t(language, 'assets.webdav.invalidUrl');
    }
    if (message === 'WebDAV 远程文件名不能包含路径分隔符。') {
      return this.t(language, 'assets.webdav.invalidFileName');
    }
    return message;
  }
}

export const ASSETS_CONTROLLER: AssetsController = new AssetsController();
