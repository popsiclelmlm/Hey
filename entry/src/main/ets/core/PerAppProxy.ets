export interface PerAppProxyImportResult {
  success: boolean;
  bypass: boolean;
  packages: Array<string>;
  count: number;
}

export const ANDROID_PACKAGE_NAME_LIST_URL: string = 'https://raw.githubusercontent.com/2dust/androidpackagenamelist/master/proxy.txt';

export const DEFAULT_PROXY_APP_PACKAGE_LIST: string = [
  'com.huawei.hbrowser',
  'com.android.chrome',
  'com.brave.browser',
  'com.discord',
  'com.dropbox.android',
  'com.duckduckgo.mobile.android',
  'com.facebook.katana',
  'com.facebook.orca',
  'com.google.android.apps.maps',
  'com.google.android.apps.translate',
  'com.google.android.gm',
  'com.google.android.gms',
  'com.google.android.googlequicksearchbox',
  'com.google.android.youtube',
  'com.instagram.android',
  'com.netflix.mediaclient',
  'com.openai.chatgpt',
  'com.reddit.frontpage',
  'com.spotify.music',
  'com.twitter.android',
  'org.mozilla.firefox',
  'org.telegram.messenger'
].join('\n');

export function normalizePerAppPackageList(packages: Array<string>, selfPackageName: string = ''): Array<string> {
  const normalized = new Array<string>();
  const seen: Record<string, boolean> = {};
  const selfKey = selfPackageName.trim().toLowerCase();
  for (let index = 0; index < packages.length; index++) {
    const item = packages[index].trim();
    const key = item.toLowerCase();
    if (!isValidPackageName(item) || key === selfKey || seen[key]) {
      continue;
    }
    seen[key] = true;
    normalized.push(item);
  }
  return normalized;
}

export function selectAllPerAppPackages(
  currentPackages: Array<string>,
  visiblePackages: Array<string>,
  selfPackageName: string = ''
): Array<string> {
  return normalizePerAppPackageList(currentPackages.concat(visiblePackages), selfPackageName);
}

export function clearVisiblePerAppPackages(
  currentPackages: Array<string>,
  visiblePackages: Array<string>,
  selfPackageName: string = ''
): Array<string> {
  const visible = normalizePerAppPackageList(visiblePackages, selfPackageName);
  const hidden: Record<string, boolean> = {};
  for (let index = 0; index < visible.length; index++) {
    hidden[visible[index].toLowerCase()] = true;
  }
  const normalized = normalizePerAppPackageList(currentPackages, selfPackageName);
  const next = new Array<string>();
  for (let index = 0; index < normalized.length; index++) {
    if (!hidden[normalized[index].toLowerCase()]) {
      next.push(normalized[index]);
    }
  }
  return next;
}

export function invertVisiblePerAppPackages(
  currentPackages: Array<string>,
  visiblePackages: Array<string>,
  selfPackageName: string = ''
): Array<string> {
  const current = normalizePerAppPackageList(currentPackages, selfPackageName);
  const visible = normalizePerAppPackageList(visiblePackages, selfPackageName);
  const selected: Record<string, boolean> = {};
  for (let index = 0; index < current.length; index++) {
    selected[current[index].toLowerCase()] = true;
  }

  for (let index = 0; index < visible.length; index++) {
    const key = visible[index].toLowerCase();
    selected[key] = !selected[key];
  }

  const next = new Array<string>();
  for (let index = 0; index < current.length; index++) {
    if (selected[current[index].toLowerCase()]) {
      next.push(current[index]);
    }
  }
  for (let index = 0; index < visible.length; index++) {
    if (selected[visible[index].toLowerCase()] && next.indexOf(visible[index]) < 0) {
      next.push(visible[index]);
    }
  }
  return next;
}

export function selectAutoProxyPackages(
  visiblePackages: Array<string>,
  bypass: boolean,
  proxyListContent: string = DEFAULT_PROXY_APP_PACKAGE_LIST,
  selfPackageName: string = '',
  forceGoogle: boolean = true
): Array<string> {
  const visible = normalizePerAppPackageList(visiblePackages, selfPackageName);
  const proxyPackages = buildPackageLookup(splitPackageList(proxyListContent));
  const selected = new Array<string>();
  for (let index = 0; index < visible.length; index++) {
    const matched = isAutoProxyPackage(proxyPackages, visible[index], forceGoogle);
    if ((bypass && !matched) || (!bypass && matched)) {
      selected.push(visible[index]);
    }
  }
  return selected;
}

export function resolveAutoProxyPackageListContent(remoteContent: string | undefined): string {
  if (remoteContent !== undefined && remoteContent.trim().length > 0) {
    return remoteContent;
  }
  return DEFAULT_PROXY_APP_PACKAGE_LIST;
}

export function exportPerAppProxyList(bypass: boolean, packages: Array<string>, selfPackageName: string = ''): string {
  const normalized = normalizePerAppPackageList(packages, selfPackageName);
  return [bypass ? 'true' : 'false'].concat(normalized).join('\n');
}

export function importPerAppProxyList(
  content: string,
  fallbackBypass: boolean,
  selfPackageName: string = ''
): PerAppProxyImportResult {
  const lines = content.split(/\r?\n/).map((line: string) => line.trim()).filter((line: string) => line.length > 0);
  if (lines.length === 0) {
    return {
      success: false,
      bypass: fallbackBypass,
      packages: [],
      count: 0
    };
  }

  let bypass = fallbackBypass;
  let startIndex = 0;
  const firstLine = lines[0].toLowerCase();
  if (firstLine === 'true' || firstLine === 'false') {
    bypass = firstLine === 'true';
    startIndex = 1;
  }

  const tokens = new Array<string>();
  for (let index = startIndex; index < lines.length; index++) {
    const parts = lines[index].split(/[\s,]+/);
    for (let partIndex = 0; partIndex < parts.length; partIndex++) {
      tokens.push(parts[partIndex]);
    }
  }
  const packages = normalizePerAppPackageList(tokens, selfPackageName);
  const success = packages.length > 0 || startIndex > 0;
  return {
    success,
    bypass,
    packages,
    count: packages.length
  };
}

function isValidPackageName(value: string): boolean {
  if (value.length < 5 || value.indexOf('.') <= 0 || value.endsWith('.')) {
    return false;
  }
  return /^[A-Za-z0-9_.$-]+$/.test(value);
}

function isAutoProxyPackage(proxyPackages: Record<string, boolean>, packageName: string, forceGoogle: boolean): boolean {
  const normalized = packageName.trim();
  const key = normalized.toLowerCase();
  if (normalized.length === 0) {
    return false;
  }
  if (forceGoogle) {
    if (key === 'com.google.android.webview') {
      return false;
    }
    if (key.startsWith('com.google')) {
      return true;
    }
  }
  return proxyPackages[key] === true;
}

function splitPackageList(content: string): Array<string> {
  const tokens = new Array<string>();
  const parts = content.split(/[\s,]+/);
  for (let index = 0; index < parts.length; index++) {
    tokens.push(parts[index]);
  }
  return tokens;
}

function buildPackageLookup(packages: Array<string>): Record<string, boolean> {
  const lookup: Record<string, boolean> = {};
  const normalized = normalizePerAppPackageList(packages);
  for (let index = 0; index < normalized.length; index++) {
    lookup[normalized[index].toLowerCase()] = true;
  }
  return lookup;
}
