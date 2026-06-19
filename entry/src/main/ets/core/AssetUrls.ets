export interface ScannedAssetUrl {
  valid: boolean;
  name: string;
  url: string;
}

export function normalizeScannedAssetUrl(value: string): ScannedAssetUrl {
  const url = value.trim();
  if (!isHttpAssetUrl(url)) {
    return { valid: false, name: '', url: '' };
  }
  return { valid: true, name: deriveAssetNameFromUrl(url), url };
}

export function deriveAssetNameFromUrl(url: string): string {
  let clean = url.trim();
  const queryIndex = clean.indexOf('?');
  if (queryIndex >= 0) {
    clean = clean.substring(0, queryIndex);
  }
  const hashIndex = clean.indexOf('#');
  if (hashIndex >= 0) {
    clean = clean.substring(0, hashIndex);
  }
  const schemeIndex = clean.indexOf('://');
  if (schemeIndex >= 0) {
    const afterScheme = clean.substring(schemeIndex + 3);
    const pathStart = afterScheme.indexOf('/');
    clean = pathStart >= 0 ? afterScheme.substring(pathStart + 1) : '';
  }
  while (clean.endsWith('/')) {
    clean = clean.substring(0, clean.length - 1);
  }
  const slashIndex = clean.lastIndexOf('/');
  let name = slashIndex >= 0 ? clean.substring(slashIndex + 1) : clean;
  if (name.toLowerCase().endsWith('.dat')) {
    name = name.substring(0, name.length - 4);
  }
  return sanitizeAssetName(name.length > 0 ? name : 'asset');
}

function isHttpAssetUrl(url: string): boolean {
  const lower = url.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

function sanitizeAssetName(name: string): string {
  let result = '';
  for (let index = 0; index < name.length; index++) {
    const char = name.substring(index, index + 1);
    if (isInvalidAssetNameChar(char)) {
      result = `${result}_`;
    } else {
      result = `${result}${char}`;
    }
  }
  const trimmed = result.trim();
  return trimmed.length > 0 ? trimmed : 'asset';
}

function isInvalidAssetNameChar(char: string): boolean {
  return char === '/' || char === '\\' || char === ':' || char === '*' || char === '?' ||
    char === '"' || char === '<' || char === '>' || char === '|';
}
