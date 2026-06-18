import { encodeUtf8ToBase64 } from './Encoding';

export const DEFAULT_WEBDAV_BACKUP_DIR: string = 'backups';
export const DEFAULT_WEBDAV_BACKUP_FILE_NAME: string = 'hey_backup.json';
export const DEFAULT_WEBDAV_TIMEOUT_SECONDS: number = 30;

export interface WebDavConfig {
  baseUrl: string;
  username: string;
  password: string;
  remoteBasePath: string;
  remoteFileName: string;
  timeoutSeconds: number;
}

export interface WebDavConfigInput {
  baseUrl?: string;
  username?: string;
  password?: string;
  remoteBasePath?: string;
  remoteFileName?: string;
  timeoutSeconds?: number;
}

export interface WebDavValidationResult {
  valid: boolean;
  message: string;
  config: WebDavConfig;
}

export interface WebDavUrlParts {
  origin: string;
  path: string;
}

export function normalizeWebDavConfig(input: WebDavConfigInput): WebDavConfig {
  return {
    baseUrl: trimTrailingSlashes(input.baseUrl ?? ''),
    username: (input.username ?? '').trim(),
    password: input.password ?? '',
    remoteBasePath: normalizeRemotePath(input.remoteBasePath ?? DEFAULT_WEBDAV_BACKUP_DIR),
    remoteFileName: normalizeRemoteFileName(input.remoteFileName ?? DEFAULT_WEBDAV_BACKUP_FILE_NAME),
    timeoutSeconds: normalizeTimeoutSeconds(input.timeoutSeconds)
  };
}

export function validateWebDavConfig(input: WebDavConfigInput): WebDavValidationResult {
  const config = normalizeWebDavConfig(input);
  if (!isHttpUrl(config.baseUrl)) {
    return {
      valid: false,
      message: 'WebDAV 服务器地址必须以 http:// 或 https:// 开头。',
      config
    };
  }
  if (config.remoteFileName.length === 0 || config.remoteFileName.indexOf('/') >= 0 || config.remoteFileName.indexOf('\\') >= 0) {
    return {
      valid: false,
      message: 'WebDAV 远程文件名不能包含路径分隔符。',
      config
    };
  }
  return {
    valid: true,
    message: 'WebDAV 配置校验通过。',
    config
  };
}

export function buildWebDavRemoteUrl(config: WebDavConfigInput, remoteFileName?: string): string {
  const normalized = normalizeWebDavConfig(config);
  const base = trimTrailingSlashes(normalized.baseUrl);
  const path = normalizeRemotePath(normalized.remoteBasePath);
  const fileName = normalizeRemoteFileName(remoteFileName ?? normalized.remoteFileName);
  if (path.length === 0) {
    return `${base}/${fileName}`;
  }
  return `${base}/${path}/${fileName}`;
}

export function buildWebDavMkcolUrls(config: WebDavConfigInput): Array<string> {
  const remoteUrl = buildWebDavRemoteUrl(config);
  const parts = splitAbsoluteUrl(remoteUrl);
  if (parts === null) {
    return [];
  }

  const dirPath = directoryPath(parts.path);
  const segments = dirPath.split('/').filter((segment: string) => segment.length > 0);
  const urls = new Array<string>();
  let accum = '';
  for (let index = 0; index < segments.length; index++) {
    accum += `/${segments[index]}`;
    urls.push(`${parts.origin}${accum}`);
  }
  return urls;
}

export function buildWebDavHeaders(config: WebDavConfigInput, contentType: string = ''): Record<string, string> {
  const normalized = normalizeWebDavConfig(config);
  const headers: Record<string, string> = {
    'User-Agent': 'Hey/0.1',
    'Accept': '*/*'
  };
  if (contentType.length > 0) {
    headers['Content-Type'] = contentType;
  }
  const authHeader = buildWebDavAuthorizationHeader(normalized.username, normalized.password);
  if (authHeader.length > 0) {
    headers['Authorization'] = authHeader;
  }
  return headers;
}

export function buildWebDavAuthorizationHeader(username: string, password: string): string {
  const trimmedUser = username.trim();
  if (trimmedUser.length === 0) {
    return '';
  }
  return `Basic ${encodeUtf8ToBase64(`${trimmedUser}:${password}`)}`;
}

export function isWebDavSuccessStatus(statusCode: number): boolean {
  return statusCode >= 200 && statusCode < 300;
}

export function isWebDavMkcolAcceptedStatus(statusCode: number): boolean {
  return statusCode === 200 || statusCode === 201 || statusCode === 204 || statusCode === 405 || statusCode === 409;
}

function normalizeRemotePath(value: string): string {
  let path = value.trim();
  while (path.indexOf('\\') >= 0) {
    path = path.replace('\\', '/');
  }
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

function normalizeRemoteFileName(value: string): string {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : DEFAULT_WEBDAV_BACKUP_FILE_NAME;
}

function normalizeTimeoutSeconds(value: number | undefined): number {
  if (value === undefined || Number.isNaN(value)) {
    return DEFAULT_WEBDAV_TIMEOUT_SECONDS;
  }
  const seconds = Math.floor(value);
  if (seconds < 5) {
    return 5;
  }
  if (seconds > 120) {
    return 120;
  }
  return seconds;
}

function trimTrailingSlashes(value: string): string {
  let result = value.trim();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

function isHttpUrl(value: string): boolean {
  const lower = value.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

function splitAbsoluteUrl(url: string): WebDavUrlParts | null {
  const schemeIndex = url.indexOf('://');
  if (schemeIndex <= 0) {
    return null;
  }
  const hostStart = schemeIndex + 3;
  const pathStart = url.indexOf('/', hostStart);
  if (pathStart < 0) {
    return {
      origin: url,
      path: '/'
    };
  }
  return {
    origin: url.substring(0, pathStart),
    path: stripQuery(url.substring(pathStart))
  };
}

function stripQuery(path: string): string {
  const queryIndex = path.indexOf('?');
  if (queryIndex >= 0) {
    return path.substring(0, queryIndex);
  }
  const hashIndex = path.indexOf('#');
  if (hashIndex >= 0) {
    return path.substring(0, hashIndex);
  }
  return path;
}

function directoryPath(path: string): string {
  const slashIndex = path.lastIndexOf('/');
  if (slashIndex <= 0) {
    return '';
  }
  return path.substring(0, slashIndex);
}
