export interface V2rayNgH2HttpSettings {
  host: Array<string>;
  path: string;
}

export function splitV2rayNgH2Hosts(value: string): Array<string> {
  return value.split(',').map((item: string) => item.trim()).filter((item: string) => item.length > 0);
}

export function buildV2rayNgH2HttpSettings(hostCsv: string, path: string): V2rayNgH2HttpSettings {
  const normalizedPath = path.trim();
  return {
    host: splitV2rayNgH2Hosts(hostCsv),
    path: normalizedPath.length > 0 ? normalizedPath : '/'
  };
}
