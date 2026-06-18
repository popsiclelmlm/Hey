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

interface RawGeoCountData {
  categoryCount?: number;
  ruleCount?: number;
}

export const GEO_DATA_FILE_SPECS: Array<GeoDataFileSpec> = [
  { fileName: 'geosite.dat', name: 'geosite', geoType: 'domain' },
  { fileName: 'geoip.dat', name: 'geoip', geoType: 'ip' }
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
