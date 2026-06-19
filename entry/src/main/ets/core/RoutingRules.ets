import { RoutingRule } from './Profile';

export type RoutingPresetId = 'chinaWhite' | 'chinaBlack' | 'global' | 'iranWhite' | 'russiaWhite';

export interface RoutingPresetInfo {
  id: RoutingPresetId;
  titleKey: string;
  detailKey: string;
}

export interface RoutingRuleImportResult {
  success: boolean;
  rules: Array<RoutingRule>;
  count: number;
}

export const ROUTING_RULE_PRESETS: Array<RoutingPresetInfo> = [
  { id: 'chinaWhite', titleKey: 'routing.preset.chinaWhite.title', detailKey: 'routing.preset.chinaWhite.detail' },
  { id: 'chinaBlack', titleKey: 'routing.preset.chinaBlack.title', detailKey: 'routing.preset.chinaBlack.detail' },
  { id: 'global', titleKey: 'routing.preset.global.title', detailKey: 'routing.preset.global.detail' },
  { id: 'iranWhite', titleKey: 'routing.preset.iranWhite.title', detailKey: 'routing.preset.iranWhite.detail' },
  { id: 'russiaWhite', titleKey: 'routing.preset.russiaWhite.title', detailKey: 'routing.preset.russiaWhite.detail' }
];

const CN_PUBLIC_DNS_IPS: Array<string> = [
  '223.5.5.5',
  '223.6.6.6',
  '2400:3200::1',
  '2400:3200:baba::1',
  '119.29.29.29',
  '1.12.12.12',
  '120.53.53.53',
  '2402:4e00::',
  '2402:4e00:1::',
  '180.76.76.76',
  '2400:da00::6666',
  '114.114.114.114',
  '114.114.115.115',
  '114.114.114.119',
  '114.114.115.119',
  '114.114.114.110',
  '114.114.115.110',
  '180.184.1.1',
  '180.184.2.2',
  '101.226.4.6',
  '218.30.118.6',
  '123.125.81.6',
  '140.207.198.6',
  '1.2.4.8',
  '210.2.4.8',
  '52.80.66.66',
  '117.50.22.22',
  '2400:7fc0:849e:200::4',
  '2404:c2c0:85d8:901::4',
  '117.50.10.10',
  '52.80.52.52',
  '2400:7fc0:849e:200::8',
  '2404:c2c0:85d8:901::8',
  '117.50.60.30',
  '52.80.60.30'
];

const GLOBAL_PUBLIC_DNS_IPS: Array<string> = [
  '1.1.1.1',
  '1.0.0.1',
  '2606:4700:4700::1111',
  '2606:4700:4700::1001',
  '1.1.1.2',
  '1.0.0.2',
  '2606:4700:4700::1112',
  '2606:4700:4700::1002',
  '1.1.1.3',
  '1.0.0.3',
  '2606:4700:4700::1113',
  '2606:4700:4700::1003',
  '8.8.8.8',
  '8.8.4.4',
  '2001:4860:4860::8888',
  '2001:4860:4860::8844',
  '94.140.14.14',
  '94.140.15.15',
  '2a10:50c0::ad1:ff',
  '2a10:50c0::ad2:ff',
  '94.140.14.15',
  '94.140.15.16',
  '2a10:50c0::bad1:ff',
  '2a10:50c0::bad2:ff',
  '94.140.14.140',
  '94.140.14.141',
  '2a10:50c0::1:ff',
  '2a10:50c0::2:ff',
  '208.67.222.222',
  '208.67.220.220',
  '2620:119:35::35',
  '2620:119:53::53',
  '208.67.222.123',
  '208.67.220.123',
  '2620:119:35::123',
  '2620:119:53::123',
  '9.9.9.9',
  '149.112.112.112',
  '2620:fe::9',
  '2620:fe::fe',
  '9.9.9.11',
  '149.112.112.11',
  '2620:fe::11',
  '2620:fe::fe:11',
  '9.9.9.10',
  '149.112.112.10',
  '2620:fe::10',
  '2620:fe::fe:10',
  '77.88.8.8',
  '77.88.8.1',
  '2a02:6b8::feed:0ff',
  '2a02:6b8:0:1::feed:0ff',
  '77.88.8.88',
  '77.88.8.2',
  '2a02:6b8::feed:bad',
  '2a02:6b8:0:1::feed:bad',
  '77.88.8.7',
  '77.88.8.3',
  '2a02:6b8::feed:a11',
  '2a02:6b8:0:1::feed:a11'
];

export function resetRoutingRulesFromPreset(existing: Array<RoutingRule>, presetId: RoutingPresetId): Array<RoutingRule> {
  return preserveLockedRules(existing).concat(buildPresetRules(presetId));
}

export function importRoutingRulesJson(existing: Array<RoutingRule>, content: string): RoutingRuleImportResult {
  const trimmed = content.trim();
  if (trimmed.length === 0) {
    return { success: false, rules: [], count: 0 };
  }

  try {
    const rawRules = JSON.parse(trimmed) as Array<RoutingRule>;
    if (!Array.isArray(rawRules)) {
      return { success: false, rules: [], count: 0 };
    }

    const imported = new Array<RoutingRule>();
    for (let index = 0; index < rawRules.length; index++) {
      const rule = normalizeRoutingRule(rawRules[index], `imported-routing-rule-${index + 1}`);
      if (hasRoutingMatcher(rule)) {
        imported.push(rule);
      }
    }
    if (imported.length === 0) {
      return { success: false, rules: [], count: 0 };
    }

    return {
      success: true,
      rules: preserveLockedRules(existing).concat(imported),
      count: imported.length
    };
  } catch (error) {
    return { success: false, rules: [], count: 0 };
  }
}

export function exportRoutingRulesJson(rules: Array<RoutingRule>): string {
  return JSON.stringify(copyRoutingRules(rules), null, 2);
}

export function copyRoutingRules(rules: Array<RoutingRule>): Array<RoutingRule> {
  const result = new Array<RoutingRule>();
  for (let index = 0; index < rules.length; index++) {
    result.push(copyRoutingRule(rules[index]));
  }
  return result;
}

export function normalizeRoutingRules(rules: Array<RoutingRule> | undefined): Array<RoutingRule> {
  if (!Array.isArray(rules)) {
    return [];
  }
  const result = new Array<RoutingRule>();
  for (let index = 0; index < rules.length; index++) {
    const rule = normalizeRoutingRule(rules[index], `routing-rule-${index + 1}`);
    if (rule.remarks.length > 0 || hasRoutingMatcher(rule)) {
      result.push(rule);
    }
  }
  return result;
}

export function hasRoutingMatcher(rule: RoutingRule): boolean {
  return rule.domain.length > 0 || rule.ip.length > 0 || rule.process.length > 0 ||
    rule.port.length > 0 || rule.protocol.length > 0 || rule.network.length > 0;
}

function buildPresetRules(presetId: RoutingPresetId): Array<RoutingRule> {
  if (presetId === 'chinaBlack') {
    return withPresetIds(presetId, [
      rule('Bypass bittorrent', 'direct', [], [], '', '', ['bittorrent']),
      rule('Block udp443', 'block', [], [], '443', 'udp', []),
      rule('Proxy Google', 'proxy', ['geosite:google'], [], '', '', []),
      rule('Direct LAN IP', 'direct', [], ['geoip:private'], '', '', []),
      rule('Direct LAN domains', 'direct', ['geosite:private'], [], '', '', []),
      rule('Proxy global DNS IP', 'proxy', [], GLOBAL_PUBLIC_DNS_IPS, '', '', []),
      rule('Proxy global DNS domains', 'proxy', [
        'domain:cloudflare-dns.com',
        'domain:one.one.one.one',
        'domain:dns.google',
        'domain:adguard-dns.com',
        'domain:opendns.com',
        'domain:umbrella.com',
        'domain:quad9.net',
        'domain:yandex.net'
      ], [], '', '', []),
      rule('Proxy popular overseas IP', 'proxy', [], [
        'geoip:facebook',
        'geoip:fastly',
        'geoip:google',
        'geoip:netflix',
        'geoip:telegram',
        'geoip:twitter'
      ], '', '', []),
      rule('Proxy GFW list', 'proxy', ['geosite:gfw', 'geosite:greatfire'], [], '', '', []),
      rule('Final direct', 'direct', [], [], '0-65535', '', [])
    ]);
  }

  if (presetId === 'global') {
    return withPresetIds(presetId, [
      rule('Block udp443', 'block', [], [], '443', 'udp', []),
      rule('Direct LAN IP', 'direct', [], ['geoip:private'], '', '', []),
      rule('Direct LAN domains', 'direct', ['geosite:private'], [], '', '', []),
      rule('Final proxy', 'proxy', [], [], '0-65535', '', [])
    ]);
  }

  if (presetId === 'iranWhite') {
    return withPresetIds(presetId, [
      rule('Block udp443', 'block', [], [], '443', 'udp', []),
      rule('Direct LAN IP', 'direct', [], ['geoip:private'], '', '', []),
      rule('Direct LAN domains', 'direct', ['geosite:private'], [], '', '', []),
      rule('Bypass Iran domains', 'direct', ['domain:ir', 'geosite:category-ir'], [], '', '', []),
      rule('Bypass Iran IP', 'direct', [], ['geoip:ir'], '', '', [])
    ]);
  }

  if (presetId === 'russiaWhite') {
    return withPresetIds(presetId, [
      rule('Bypass bittorrent', 'direct', [], [], '', '', ['bittorrent']),
      rule('Block udp443', 'block', [], [], '443', 'udp', []),
      rule('Direct LAN IP', 'direct', [], ['geoip:private'], '', '', []),
      rule('Direct LAN domains', 'direct', ['geosite:private'], [], '', '', []),
      rule('Bypass Russia domains', 'direct', ['geosite:category-ru'], [], '', '', []),
      rule('Bypass Russia IP', 'direct', [], ['geoip:ru'], '', '', [])
    ]);
  }

  return withPresetIds(presetId, [
    rule('Block udp443', 'block', [], [], '443', 'udp', []),
    rule('Proxy Google', 'proxy', ['geosite:google'], [], '', '', []),
    rule('Direct LAN IP', 'direct', [], ['geoip:private'], '', '', []),
    rule('Direct LAN domains', 'direct', ['geosite:private'], [], '', '', []),
    rule('Direct CN public DNS IP', 'direct', [], CN_PUBLIC_DNS_IPS, '', '', []),
    rule('Direct CN public DNS domains', 'direct', [
      'domain:alidns.com',
      'domain:doh.pub',
      'domain:dot.pub',
      'domain:360.cn',
      'domain:onedns.net'
    ], [], '', '', []),
    rule('Direct CN IP', 'direct', [], ['geoip:cn'], '', '', []),
    rule('Direct CN domains', 'direct', ['geosite:cn'], [], '', '', [])
  ]);
}

function withPresetIds(presetId: RoutingPresetId, rules: Array<RoutingRule>): Array<RoutingRule> {
  for (let index = 0; index < rules.length; index++) {
    rules[index].id = `preset-${presetId}-${index + 1}`;
  }
  return rules;
}

function preserveLockedRules(rules: Array<RoutingRule>): Array<RoutingRule> {
  const locked = new Array<RoutingRule>();
  for (let index = 0; index < rules.length; index++) {
    if (rules[index].locked) {
      locked.push(copyRoutingRule(rules[index]));
    }
  }
  return locked;
}

function normalizeRoutingRule(item: RoutingRule, fallbackId: string): RoutingRule {
  return {
    id: nonEmptyString(item.id, fallbackId),
    remarks: stringValue(item.remarks, '').trim(),
    domain: cleanStringArray(item.domain),
    ip: cleanStringArray(item.ip),
    process: cleanStringArray(item.process),
    outboundTag: outboundTagValue(item.outboundTag),
    port: stringValue(item.port, '').trim(),
    network: networkValue(item.network),
    protocol: cleanStringArray(item.protocol),
    enabled: boolValue(item.enabled, true),
    locked: boolValue(item.locked, false)
  };
}

function rule(
  remarks: string,
  outboundTag: string,
  domain: Array<string>,
  ip: Array<string>,
  port: string,
  network: string,
  protocol: Array<string>
): RoutingRule {
  return {
    id: '',
    remarks,
    domain,
    ip,
    process: [],
    outboundTag,
    port,
    network,
    protocol,
    enabled: true,
    locked: false
  };
}

function copyRoutingRule(rule: RoutingRule): RoutingRule {
  return {
    id: rule.id,
    remarks: rule.remarks,
    domain: rule.domain.slice(),
    ip: rule.ip.slice(),
    process: rule.process.slice(),
    outboundTag: rule.outboundTag,
    port: rule.port,
    network: rule.network,
    protocol: rule.protocol.slice(),
    enabled: rule.enabled,
    locked: rule.locked
  };
}

function cleanStringArray(value: string[] | undefined): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const result = new Array<string>();
  for (let index = 0; index < value.length; index++) {
    const item = stringValue(value[index], '').trim();
    if (item.length > 0 && result.indexOf(item) < 0) {
      result.push(item);
    }
  }
  return result;
}

function nonEmptyString(value: string | undefined, fallback: string): string {
  const normalized = stringValue(value, '').trim();
  return normalized.length > 0 ? normalized : fallback;
}

function stringValue(value: string | undefined, fallback: string): string {
  return value === undefined ? fallback : `${value}`;
}

function boolValue(value: boolean | undefined, fallback: boolean): boolean {
  return value === undefined ? fallback : value;
}

function outboundTagValue(value: string | undefined): string {
  const normalized = stringValue(value, 'proxy').trim();
  if (normalized === 'direct' || normalized === 'block' || normalized === 'proxy' ||
    normalized === 'proxy-chain' || normalized === 'policy-group') {
    return normalized;
  }
  return 'proxy';
}

function networkValue(value: string | undefined): string {
  const normalized = stringValue(value, '').trim().toLowerCase();
  if (normalized === 'tcp' || normalized === 'udp' || normalized === 'tcp,udp' || normalized === 'udp,tcp') {
    return normalized === 'udp,tcp' ? 'tcp,udp' : normalized;
  }
  return '';
}
