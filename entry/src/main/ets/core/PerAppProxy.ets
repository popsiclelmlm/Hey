export interface PerAppProxyImportResult {
  success: boolean;
  bypass: boolean;
  packages: Array<string>;
  count: number;
}

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
