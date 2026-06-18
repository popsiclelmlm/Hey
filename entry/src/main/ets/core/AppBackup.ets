export const APP_BACKUP_MARKER: string = 'hey_backup';
export const APP_BACKUP_VERSION: string = '1';

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
