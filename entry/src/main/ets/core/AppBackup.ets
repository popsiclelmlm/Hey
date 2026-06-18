import { decodeUtf8Bytes, encodeUtf8ToBytes } from './Encoding';

export const APP_BACKUP_MARKER: string = 'hey_backup';
export const APP_BACKUP_VERSION: string = '1';
export const APP_BACKUP_ZIP_ENTRY_NAME: string = 'hey_backup.json';

export interface AppBackupPayload {
  hey_backup: boolean;
  version: string;
  createdAt: number;
  profile: string;
  settings: string;
  subscription: string;
  assets: string;
}

export interface AppBackupParseResult {
  valid: boolean;
  message: string;
  payload: AppBackupPayload | null;
}

export function buildAppBackupPayload(profile: string, settings: string, subscription: string, assets: string, createdAt: number = Date.now()): string {
  const payload: AppBackupPayload = {
    hey_backup: true,
    version: APP_BACKUP_VERSION,
    createdAt,
    profile,
    settings,
    subscription,
    assets
  };
  return JSON.stringify(payload);
}

export function buildAppBackupZip(profile: string, settings: string, subscription: string, assets: string, createdAt: number = Date.now()): ArrayBuffer {
  return buildAppBackupZipFromPayload(buildAppBackupPayload(profile, settings, subscription, assets, createdAt));
}

export function buildAppBackupZipFromPayload(payloadText: string): ArrayBuffer {
  return bytesToArrayBuffer(buildStoredZipBytes(APP_BACKUP_ZIP_ENTRY_NAME, payloadText));
}

export function parseAppBackupData(input: string | ArrayBuffer): AppBackupParseResult {
  if (typeof input === 'string') {
    return parseAppBackupPayload(input);
  }
  try {
    const bytes = arrayBufferToBytes(input);
    if (isZipBytes(bytes)) {
      return parseAppBackupPayload(extractBackupPayloadFromZip(bytes));
    }
    return parseAppBackupPayload(decodeUtf8Bytes(bytes));
  } catch (error) {
    return invalidBackup(`备份数据解析失败：${JSON.stringify(error)}`);
  }
}

export function parseAppBackupPayload(input: string): AppBackupParseResult {
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    return invalidBackup('备份数据为空。');
  }

  try {
    const parsed = JSON.parse(trimmed) as Record<string, Object>;
    if (parsed[APP_BACKUP_MARKER] !== true) {
      return invalidBackup('备份数据标记无效。');
    }
    const payload: AppBackupPayload = {
      hey_backup: true,
      version: stringValue(parsed['version'], APP_BACKUP_VERSION),
      createdAt: numberValue(parsed['createdAt'], 0),
      profile: stringValue(parsed['profile'], ''),
      settings: stringValue(parsed['settings'], ''),
      subscription: stringValue(parsed['subscription'], ''),
      assets: stringValue(parsed['assets'], '')
    };
    return {
      valid: true,
      message: '备份数据校验通过。',
      payload
    };
  } catch (error) {
    return invalidBackup(`备份数据解析失败：${JSON.stringify(error)}`);
  }
}

function buildStoredZipBytes(fileName: string, content: string): Array<number> {
  const fileNameBytes = encodeUtf8ToBytes(fileName);
  const contentBytes = encodeUtf8ToBytes(content);
  const crc = crc32(contentBytes);
  const localHeaderOffset = 0;
  const bytes: Array<number> = [];

  writeU32(bytes, 0x04034B50);
  writeU16(bytes, 20);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU32(bytes, crc);
  writeU32(bytes, contentBytes.length);
  writeU32(bytes, contentBytes.length);
  writeU16(bytes, fileNameBytes.length);
  writeU16(bytes, 0);
  appendBytes(bytes, fileNameBytes);
  appendBytes(bytes, contentBytes);

  const centralDirectoryOffset = bytes.length;
  writeU32(bytes, 0x02014B50);
  writeU16(bytes, 20);
  writeU16(bytes, 20);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU32(bytes, crc);
  writeU32(bytes, contentBytes.length);
  writeU32(bytes, contentBytes.length);
  writeU16(bytes, fileNameBytes.length);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU32(bytes, 0);
  writeU32(bytes, localHeaderOffset);
  appendBytes(bytes, fileNameBytes);

  const centralDirectorySize = bytes.length - centralDirectoryOffset;
  writeU32(bytes, 0x06054B50);
  writeU16(bytes, 0);
  writeU16(bytes, 0);
  writeU16(bytes, 1);
  writeU16(bytes, 1);
  writeU32(bytes, centralDirectorySize);
  writeU32(bytes, centralDirectoryOffset);
  writeU16(bytes, 0);
  return bytes;
}

function extractBackupPayloadFromZip(bytes: Array<number>): string {
  const eocdOffset = findEndOfCentralDirectory(bytes);
  if (eocdOffset < 0) {
    throw new Error('ZIP 目录无效。');
  }
  const entryCount = readU16(bytes, eocdOffset + 10);
  const centralDirectoryOffset = readU32(bytes, eocdOffset + 16);
  let offset = centralDirectoryOffset;
  for (let index = 0; index < entryCount; index++) {
    if (readU32(bytes, offset) !== 0x02014B50) {
      throw new Error('ZIP 中央目录项无效。');
    }
    const method = readU16(bytes, offset + 10);
    const compressedSize = readU32(bytes, offset + 20);
    const fileNameLength = readU16(bytes, offset + 28);
    const extraLength = readU16(bytes, offset + 30);
    const commentLength = readU16(bytes, offset + 32);
    const localOffset = readU32(bytes, offset + 42);
    const fileName = decodeUtf8Bytes(bytes.slice(offset + 46, offset + 46 + fileNameLength));
    if (fileName === APP_BACKUP_ZIP_ENTRY_NAME) {
      if (method !== 0) {
        throw new Error('ZIP 备份暂只支持 stored 条目。');
      }
      return decodeUtf8Bytes(readStoredLocalFile(bytes, localOffset, compressedSize));
    }
    offset += 46 + fileNameLength + extraLength + commentLength;
  }
  throw new Error('ZIP 备份缺少 hey_backup.json。');
}

function readStoredLocalFile(bytes: Array<number>, offset: number, size: number): Array<number> {
  if (readU32(bytes, offset) !== 0x04034B50) {
    throw new Error('ZIP 本地文件头无效。');
  }
  const fileNameLength = readU16(bytes, offset + 26);
  const extraLength = readU16(bytes, offset + 28);
  const dataOffset = offset + 30 + fileNameLength + extraLength;
  return bytes.slice(dataOffset, dataOffset + size);
}

function isZipBytes(bytes: Array<number>): boolean {
  return bytes.length >= 4 && readU32(bytes, 0) === 0x04034B50;
}

function findEndOfCentralDirectory(bytes: Array<number>): number {
  const minOffset = Math.max(0, bytes.length - 65557);
  for (let offset = bytes.length - 22; offset >= minOffset; offset--) {
    if (readU32(bytes, offset) === 0x06054B50) {
      return offset;
    }
  }
  return -1;
}

function crc32(bytes: Array<number>): number {
  let crc = 0xFFFFFFFF;
  for (let index = 0; index < bytes.length; index++) {
    crc = (crc ^ bytes[index]) >>> 0;
    for (let bit = 0; bit < 8; bit++) {
      const mask = (crc & 1) === 1 ? 0xEDB88320 : 0;
      crc = ((crc >>> 1) ^ mask) >>> 0;
    }
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function appendBytes(target: Array<number>, source: Array<number>): void {
  for (let index = 0; index < source.length; index++) {
    target.push(source[index] & 0xFF);
  }
}

function writeU16(target: Array<number>, value: number): void {
  target.push(value & 0xFF);
  target.push((value >>> 8) & 0xFF);
}

function writeU32(target: Array<number>, value: number): void {
  target.push(value & 0xFF);
  target.push((value >>> 8) & 0xFF);
  target.push((value >>> 16) & 0xFF);
  target.push((value >>> 24) & 0xFF);
}

function readU16(bytes: Array<number>, offset: number): number {
  return (bytes[offset] | (bytes[offset + 1] << 8)) >>> 0;
}

function readU32(bytes: Array<number>, offset: number): number {
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
}

function arrayBufferToBytes(buffer: ArrayBuffer): Array<number> {
  const view = new Uint8Array(buffer);
  const bytes: Array<number> = [];
  for (let index = 0; index < view.length; index++) {
    bytes.push(view[index]);
  }
  return bytes;
}

function bytesToArrayBuffer(bytes: Array<number>): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.length);
  const view = new Uint8Array(buffer);
  for (let index = 0; index < bytes.length; index++) {
    view[index] = bytes[index] & 0xFF;
  }
  return buffer;
}

function invalidBackup(message: string): AppBackupParseResult {
  return {
    valid: false,
    message,
    payload: null
  };
}

function stringValue(value: Object | undefined, fallback: string): string {
  if (typeof value === 'string') {
    return value;
  }
  if (value === undefined || value === null) {
    return fallback;
  }
  return value.toString();
}

function numberValue(value: Object | undefined, fallback: number): number {
  if (typeof value === 'number' && !Number.isNaN(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isNaN(parsed) ? fallback : Math.floor(parsed);
  }
  return fallback;
}
