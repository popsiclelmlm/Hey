import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { encodeUtf8ToBytes } from '../core/Encoding';
import {
  buildWebDavHeaders,
  buildWebDavMkcolUrls,
  buildWebDavRemoteUrl,
  isWebDavSuccessStatus,
  validateWebDavConfig,
  WebDavConfigInput
} from '../core/WebDav';

export interface WebDavTransferResult {
  ok: boolean;
  message: string;
  remoteUrl: string;
  responseCode: number;
  content: string;
  data: ArrayBuffer | null;
}

export class WebDavManager {
  async uploadText(config: WebDavConfigInput, content: string): Promise<WebDavTransferResult> {
    const validation = validateWebDavConfig(config);
    if (!validation.valid) {
      return this.failure(validation.message, '', 0);
    }

    const remoteUrl = buildWebDavRemoteUrl(validation.config);
    const mkcolUrls = buildWebDavMkcolUrls(validation.config);
    for (let index = 0; index < mkcolUrls.length; index++) {
      await this.requestText(mkcolUrls[index], 'MKCOL', validation.config, '', '');
    }

    const result = await this.requestText(remoteUrl, 'PUT', validation.config, 'application/json; charset=utf-8', content);
    if (!isWebDavSuccessStatus(result.responseCode)) {
      return this.failure(`WebDAV 上传失败：HTTP ${result.responseCode}`, remoteUrl, result.responseCode);
    }
    return {
      ok: true,
      message: 'WebDAV 备份上传成功。',
      remoteUrl,
      responseCode: result.responseCode,
      content: '',
      data: null
    };
  }

  async uploadData(config: WebDavConfigInput, data: ArrayBuffer, contentType: string = 'application/zip'): Promise<WebDavTransferResult> {
    const validation = validateWebDavConfig(config);
    if (!validation.valid) {
      return this.failure(validation.message, '', 0);
    }

    const remoteUrl = buildWebDavRemoteUrl(validation.config);
    const mkcolUrls = buildWebDavMkcolUrls(validation.config);
    for (let index = 0; index < mkcolUrls.length; index++) {
      await this.requestText(mkcolUrls[index], 'MKCOL', validation.config, '', '');
    }

    const result = await this.requestData(remoteUrl, 'PUT', validation.config, contentType, data);
    if (!isWebDavSuccessStatus(result.responseCode)) {
      return this.failure(`WebDAV 上传失败：HTTP ${result.responseCode}`, remoteUrl, result.responseCode);
    }
    return {
      ok: true,
      message: 'WebDAV 备份上传成功。',
      remoteUrl,
      responseCode: result.responseCode,
      content: '',
      data: null
    };
  }

  async downloadText(config: WebDavConfigInput): Promise<WebDavTransferResult> {
    const validation = validateWebDavConfig(config);
    if (!validation.valid) {
      return this.failure(validation.message, '', 0);
    }

    const remoteUrl = buildWebDavRemoteUrl(validation.config);
    const result = await this.requestText(remoteUrl, 'GET', validation.config, '', '');
    if (!isWebDavSuccessStatus(result.responseCode)) {
      return this.failure(`WebDAV 下载失败：HTTP ${result.responseCode}`, remoteUrl, result.responseCode);
    }
    return {
      ok: true,
      message: 'WebDAV 备份下载成功。',
      remoteUrl,
      responseCode: result.responseCode,
      content: result.content,
      data: null
    };
  }

  async downloadData(config: WebDavConfigInput): Promise<WebDavTransferResult> {
    const validation = validateWebDavConfig(config);
    if (!validation.valid) {
      return this.failure(validation.message, '', 0);
    }

    const remoteUrl = buildWebDavRemoteUrl(validation.config);
    const result = await this.requestData(remoteUrl, 'GET', validation.config, '', new ArrayBuffer(0));
    if (!isWebDavSuccessStatus(result.responseCode)) {
      return this.failure(`WebDAV 下载失败：HTTP ${result.responseCode}`, remoteUrl, result.responseCode);
    }
    return {
      ok: true,
      message: 'WebDAV 备份下载成功。',
      remoteUrl,
      responseCode: result.responseCode,
      content: '',
      data: result.data
    };
  }

  private async requestText(url: string, method: string, config: WebDavConfigInput, contentType: string, body: string): Promise<WebDavTransferResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: this.requestMethod(method),
        expectDataType: http.HttpDataType.STRING,
        readTimeout: (config.timeoutSeconds ?? 30) * 1000,
        connectTimeout: (config.timeoutSeconds ?? 30) * 1000,
        usingCache: false,
        header: buildWebDavHeaders(config, contentType)
      };
      if (body.length > 0) {
        options.extraData = body;
      }

      const response = await request.request(url, options);
      const responseCode = Number(response.responseCode);
      return {
        ok: isWebDavSuccessStatus(responseCode),
        message: '',
        remoteUrl: url,
        responseCode,
        content: this.responseText(response.result),
        data: null
      };
    } catch (error) {
      return this.failure(`WebDAV 请求失败：${error instanceof Error ? error.message : JSON.stringify(error)}`, url, 0);
    } finally {
      request.destroy();
    }
  }

  private async requestData(url: string, method: string, config: WebDavConfigInput, contentType: string, body: ArrayBuffer): Promise<WebDavTransferResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: this.requestMethod(method),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: (config.timeoutSeconds ?? 30) * 1000,
        connectTimeout: (config.timeoutSeconds ?? 30) * 1000,
        usingCache: false,
        header: buildWebDavHeaders(config, contentType)
      };
      if (body.byteLength > 0) {
        options.extraData = body;
      }

      const response = await request.request(url, options);
      const responseCode = Number(response.responseCode);
      return {
        ok: isWebDavSuccessStatus(responseCode),
        message: '',
        remoteUrl: url,
        responseCode,
        content: '',
        data: this.responseData(response.result)
      };
    } catch (error) {
      return this.failure(`WebDAV 请求失败：${error instanceof Error ? error.message : JSON.stringify(error)}`, url, 0);
    } finally {
      request.destroy();
    }
  }

  private requestMethod(method: string): http.RequestMethod {
    return method as http.RequestMethod;
  }

  private responseText(result: Object | string | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decode(new Uint8Array(result));
    }
    const text = JSON.stringify(result);
    return text === undefined ? '' : text;
  }

  private responseData(result: Object | string | ArrayBuffer): ArrayBuffer {
    if (result instanceof ArrayBuffer) {
      return result;
    }
    if (typeof result === 'string') {
      return this.bytesToArrayBuffer(encodeUtf8ToBytes(result));
    }
    const text = JSON.stringify(result);
    return this.bytesToArrayBuffer(encodeUtf8ToBytes(text === undefined ? '' : text));
  }

  private bytesToArrayBuffer(bytes: Array<number>): ArrayBuffer {
    const buffer = new ArrayBuffer(bytes.length);
    const view = new Uint8Array(buffer);
    for (let index = 0; index < bytes.length; index++) {
      view[index] = bytes[index] & 0xFF;
    }
    return buffer;
  }

  private failure(message: string, remoteUrl: string, responseCode: number): WebDavTransferResult {
    return {
      ok: false,
      message,
      remoteUrl,
      responseCode,
      content: '',
      data: null
    };
  }
}

export const WEBDAV_MANAGER: WebDavManager = new WebDavManager();
