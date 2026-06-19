import { AppLanguage } from './Profile';
import { formatOne, formatTwo } from '../utils/LocalizationPresenter';

export type GeoDataType = 'domain' | 'ip';

export interface GeoDataFileSpec {
  fileName: string;
  name: string;
  geoType: GeoDataType;
}

export interface GeoCountData {
  categoryCount: number;
  ruleCount: number;
}

export const GEOSITE_FILE_NAME: string = 'geosite.dat';
export const GEOIP_FILE_NAME: string = 'geoip.dat';
export const GEOIP_ONLY_CN_PRIVATE_FILE_NAME: string = 'geoip-only-cn-private.dat';
export const GEOIP_ONLY_CN_PRIVATE_URL: string =
  'https://raw.githubusercontent.com/Loyalsoldier/geoip/release/geoip-only-cn-private.dat';
export const BUILTIN_GEO_DATA_FILE_NAMES: Array<string> = [
  GEOSITE_FILE_NAME,
  GEOIP_FILE_NAME,
  GEOIP_ONLY_CN_PRIVATE_FILE_NAME
];

interface RawGeoCountData {
  categoryCount?: number;
  ruleCount?: number;
}

export const GEO_DATA_FILE_SPECS: Array<GeoDataFileSpec> = [
  { fileName: GEOSITE_FILE_NAME, name: 'geosite', geoType: 'domain' },
  { fileName: GEOIP_FILE_NAME, name: 'geoip', geoType: 'ip' },
  { fileName: GEOIP_ONLY_CN_PRIVATE_FILE_NAME, name: 'geoip-only-cn-private', geoType: 'ip' }
];

export function geoDataSpecForFile(fileName: string): GeoDataFileSpec | null {
  for (let index = 0; index < GEO_DATA_FILE_SPECS.length; index++) {
    const item = GEO_DATA_FILE_SPECS[index];
    if (item.fileName === fileName) {
      return item;
    }
  }
  return null;
}

export function parseGeoCountData(raw: string): GeoCountData | null {
  try {
    const parsed = JSON.parse(raw) as RawGeoCountData;
    const categoryCount = parsed.categoryCount;
    const ruleCount = parsed.ruleCount;
    if (typeof categoryCount !== 'number' || typeof ruleCount !== 'number') {
      return null;
    }
    return { categoryCount, ruleCount };
  } catch (error) {
    return null;
  }
}

export function buildBuiltinGeoAssetUrl(sourceUrl: string, fileName: string): string {
  if (fileName === GEOIP_ONLY_CN_PRIVATE_FILE_NAME) {
    return GEOIP_ONLY_CN_PRIVATE_URL;
  }
  const normalizedSource = sourceUrl.endsWith('/') ? sourceUrl : `${sourceUrl}/`;
  return `${normalizedSource}${fileName}`;
}

export function formatGeoCountSummary(language: AppLanguage, count: GeoCountData): string {
  return formatTwo(
    language,
    'assets.geoCount',
    'categories',
    count.categoryCount.toString(),
    'rules',
    count.ruleCount.toString()
  );
}

export function formatGeoCountUnavailable(language: AppLanguage, error: string): string {
  return formatOne(language, 'assets.geoCountUnavailable', 'error', error);
}
