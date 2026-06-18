export const CURRENT_APP_VERSION: string = '1.1.0';
export const HEY_RELEASES_API_URL: string = 'https://api.github.com/repos/popsiclelmlm/Hey/releases';
export const HEY_LATEST_RELEASE_API_URL: string = `${HEY_RELEASES_API_URL}/latest`;
export const HEY_RELEASES_PAGE_URL: string = 'https://github.com/popsiclelmlm/Hey/releases';

export interface UpdateCheckResult {
  ok: boolean;
  hasUpdate: boolean;
  currentVersion: string;
  latestVersion: string;
  releaseNotes: string;
  downloadUrl: string;
  isPreRelease: boolean;
  error: string;
}

interface GitHubReleaseAsset {
  name: string;
  browser_download_url: string;
}

interface GitHubRelease {
  tagName: string;
  body: string;
  assets: Array<GitHubReleaseAsset>;
  prerelease: boolean;
  htmlUrl: string;
}

export function buildUpdateCheckResult(content: string, currentVersion: string = CURRENT_APP_VERSION): UpdateCheckResult {
  const release = parseGitHubRelease(content);
  if (release === null) {
    return updateFailed(currentVersion, 'invalid-release');
  }

  const latestVersion = normalizeVersionTag(release.tagName);
  if (latestVersion.length === 0) {
    return updateFailed(currentVersion, 'missing-version');
  }

  const hasUpdate = compareVersions(latestVersion, currentVersion) > 0;
  return {
    ok: true,
    hasUpdate,
    currentVersion,
    latestVersion,
    releaseNotes: release.body,
    downloadUrl: hasUpdate ? selectReleaseDownloadUrl(release) : '',
    isPreRelease: release.prerelease,
    error: ''
  };
}

export function compareVersions(versionA: string, versionB: string): number {
  const left = versionParts(versionA);
  const right = versionParts(versionB);
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    const a = index < left.length ? left[index] : 0;
    const b = index < right.length ? right[index] : 0;
    if (a !== b) {
      return a - b;
    }
  }
  return 0;
}

export function normalizeVersionTag(tag: string): string {
  let value = tag.trim();
  while (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  const separator = value.indexOf('-');
  if (separator >= 0) {
    value = value.substring(0, separator);
  }
  return value.trim();
}

function parseGitHubRelease(content: string): GitHubRelease | null {
  try {
    const parsed = JSON.parse(content) as Object;
    if (Array.isArray(parsed)) {
      const releases = parsed as Array<Object>;
      return releases.length > 0 ? releaseFromObject(releases[0]) : null;
    }
    return releaseFromObject(parsed);
  } catch (error) {
    return null;
  }
}

function releaseFromObject(value: Object): GitHubRelease | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, Object>;
  const tagName = stringValue(record['tag_name'], stringValue(record['name'], ''));
  if (tagName.length === 0) {
    return null;
  }
  return {
    tagName,
    body: stringValue(record['body'], ''),
    assets: assetsFromValue(record['assets']),
    prerelease: record['prerelease'] === true,
    htmlUrl: stringValue(record['html_url'], HEY_RELEASES_PAGE_URL)
  };
}

function assetsFromValue(value: Object | undefined): Array<GitHubReleaseAsset> {
  if (!Array.isArray(value)) {
    return [];
  }
  const assets = new Array<GitHubReleaseAsset>();
  const rawAssets = value as Array<Object>;
  for (let index = 0; index < rawAssets.length; index++) {
    const raw = rawAssets[index];
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      continue;
    }
    const record = raw as Record<string, Object>;
    const name = stringValue(record['name'], '');
    const url = stringValue(record['browser_download_url'], '');
    if (name.length > 0 && url.length > 0) {
      assets.push({
        name,
        browser_download_url: url
      });
    }
  }
  return assets;
}

function selectReleaseDownloadUrl(release: GitHubRelease): string {
  if (release.assets.length === 0) {
    return release.htmlUrl.length > 0 ? release.htmlUrl : HEY_RELEASES_PAGE_URL;
  }
  let bestIndex = 0;
  let bestScore = releaseAssetScore(release.assets[0].name);
  for (let index = 1; index < release.assets.length; index++) {
    const score = releaseAssetScore(release.assets[index].name);
    if (score > bestScore) {
      bestIndex = index;
      bestScore = score;
    }
  }
  return release.assets[bestIndex].browser_download_url;
}

function releaseAssetScore(name: string): number {
  const normalized = name.toLowerCase();
  let score = 0;
  if (normalized.endsWith('.hap')) {
    score += 80;
  }
  if (normalized.endsWith('.app')) {
    score += 70;
  }
  if (normalized.indexOf('harmony') >= 0 || normalized.indexOf('ohos') >= 0) {
    score += 30;
  }
  if (normalized.indexOf('arm64') >= 0 || normalized.indexOf('aarch64') >= 0) {
    score += 20;
  }
  if (normalized.indexOf('universal') >= 0) {
    score += 10;
  }
  if (normalized.indexOf('source') >= 0) {
    score -= 40;
  }
  return score;
}

function versionParts(version: string): Array<number> {
  const parts = normalizeVersionTag(version).split('.');
  const result = new Array<number>();
  for (let index = 0; index < parts.length; index++) {
    result.push(numberPrefix(parts[index]));
  }
  return result;
}

function numberPrefix(value: string): number {
  let digits = '';
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code < 48 || code > 57) {
      break;
    }
    digits += value[index];
  }
  if (digits.length === 0) {
    return 0;
  }
  const parsed = Number(digits);
  return Number.isNaN(parsed) ? 0 : Math.floor(parsed);
}

function stringValue(value: Object | undefined, fallback: string): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (value === undefined || value === null) {
    return fallback;
  }
  return value.toString().trim();
}

function updateFailed(currentVersion: string, error: string): UpdateCheckResult {
  return {
    ok: false,
    hasUpdate: false,
    currentVersion,
    latestVersion: '',
    releaseNotes: '',
    downloadUrl: '',
    isPreRelease: false,
    error
  };
}
