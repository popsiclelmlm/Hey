import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DEFAULT_LANGUAGE, normalizeLanguage } from '../core/I18n';
import { AppLanguage, AppSettings, RoutingRule } from '../core/Profile';

const PREFERENCES_NAME: string = 'hey_vpn_settings';
const SETTINGS_KEY: string = 'app_settings';

export const DEFAULT_APP_SETTINGS: AppSettings = {
  language: DEFAULT_LANGUAGE,
  sniffingEnabled: true,
  routeOnlyEnabled: false,
  perAppProxyEnabled: false,
  perAppProxyList: [],
  perAppProxyBypass: true,
  localDnsEnabled: false,
  fakeDnsEnabled: false,
  appendHttpProxy: false,
  muxEnabled: false,
  muxConcurrency: 8,
  muxXudpConcurrency: 8,
  muxXudpQuic: 'reject',
  fragmentEnabled: false,
  fragmentPackets: 'tlshello',
  fragmentLength: '50-100',
  fragmentInterval: '10-20',
  preferIpv6: false,
  proxySharingEnabled: false,
  allowInsecure: false,
  localDnsPort: 10853,
  vpnDns: '1.1.1.1',
  remoteDns: '1.1.1.1',
  domesticDns: '223.5.5.5',
  dnsHosts: '',
  delayTestUrl: 'https://www.gstatic.com/generate_204',
  logLevel: 'warning',
  mode: 'VPN',
  trafficMode: 'rules',
  routingDomainStrategy: 'AsIs',
  adBlockEnabled: false,
  routingRules: [],
  autoSortAfterTest: false,
  autoRemoveInvalidAfterTest: false
};

export class SettingsStore {
  static async load(context: common.Context): Promise<AppSettings> {
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    const rawValue = await store.get(SETTINGS_KEY, '');
    const raw = rawValue.toString();
    if (raw.length === 0) {
      return SettingsStore.copy(DEFAULT_APP_SETTINGS);
    }

    try {
      return SettingsStore.normalize(JSON.parse(raw) as AppSettings);
    } catch (error) {
      return SettingsStore.copy(DEFAULT_APP_SETTINGS);
    }
  }

  static async save(context: common.Context, settings: AppSettings): Promise<AppSettings> {
    const normalized = SettingsStore.normalize(settings);
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    await store.put(SETTINGS_KEY, JSON.stringify(normalized));
    await store.flush();
    return normalized;
  }

  static async saveLanguage(context: common.Context, language: AppLanguage): Promise<AppSettings> {
    const settings = await SettingsStore.load(context);
    settings.language = language;
    return SettingsStore.save(context, settings);
  }

  private static normalize(raw: AppSettings): AppSettings {
    const base = SettingsStore.copy(DEFAULT_APP_SETTINGS);
    return {
      language: normalizeLanguage(raw.language),
      sniffingEnabled: SettingsStore.boolValue(raw.sniffingEnabled, base.sniffingEnabled),
      routeOnlyEnabled: SettingsStore.boolValue(raw.routeOnlyEnabled, base.routeOnlyEnabled),
      perAppProxyEnabled: SettingsStore.boolValue(raw.perAppProxyEnabled, base.perAppProxyEnabled),
      perAppProxyList: SettingsStore.arrayValue(raw.perAppProxyList, base.perAppProxyList),
      perAppProxyBypass: SettingsStore.boolValue(raw.perAppProxyBypass, base.perAppProxyBypass),
      localDnsEnabled: SettingsStore.boolValue(raw.localDnsEnabled, base.localDnsEnabled),
      fakeDnsEnabled: SettingsStore.boolValue(raw.fakeDnsEnabled, base.fakeDnsEnabled),
      appendHttpProxy: SettingsStore.boolValue(raw.appendHttpProxy, base.appendHttpProxy),
      muxEnabled: SettingsStore.boolValue(raw.muxEnabled, base.muxEnabled),
      muxConcurrency: SettingsStore.numberValue(raw.muxConcurrency, base.muxConcurrency),
      muxXudpConcurrency: SettingsStore.numberValue(raw.muxXudpConcurrency, base.muxXudpConcurrency),
      muxXudpQuic: SettingsStore.stringValue(raw.muxXudpQuic, base.muxXudpQuic),
      fragmentEnabled: SettingsStore.boolValue(raw.fragmentEnabled, base.fragmentEnabled),
      fragmentPackets: SettingsStore.stringValue(raw.fragmentPackets, base.fragmentPackets),
      fragmentLength: SettingsStore.stringValue(raw.fragmentLength, base.fragmentLength),
      fragmentInterval: SettingsStore.stringValue(raw.fragmentInterval, base.fragmentInterval),
      preferIpv6: SettingsStore.boolValue(raw.preferIpv6, base.preferIpv6),
      proxySharingEnabled: SettingsStore.boolValue(raw.proxySharingEnabled, base.proxySharingEnabled),
      allowInsecure: SettingsStore.boolValue(raw.allowInsecure, base.allowInsecure),
      localDnsPort: SettingsStore.portValue(raw.localDnsPort, base.localDnsPort),
      vpnDns: SettingsStore.stringValue(raw.vpnDns, base.vpnDns),
      remoteDns: SettingsStore.stringValue(raw.remoteDns, base.remoteDns),
      domesticDns: SettingsStore.stringValue(raw.domesticDns, base.domesticDns),
      dnsHosts: SettingsStore.stringValue(raw.dnsHosts, base.dnsHosts),
      delayTestUrl: SettingsStore.stringValue(raw.delayTestUrl, base.delayTestUrl),
      logLevel: SettingsStore.stringValue(raw.logLevel, base.logLevel),
      mode: SettingsStore.stringValue(raw.mode, base.mode),
      trafficMode: SettingsStore.trafficModeValue(raw.trafficMode, base.trafficMode),
      routingDomainStrategy: SettingsStore.stringValue(raw.routingDomainStrategy, base.routingDomainStrategy),
      adBlockEnabled: SettingsStore.boolValue(raw.adBlockEnabled, base.adBlockEnabled),
      routingRules: SettingsStore.routingRulesValue(raw.routingRules),
      autoSortAfterTest: SettingsStore.boolValue(raw.autoSortAfterTest, base.autoSortAfterTest),
      autoRemoveInvalidAfterTest: SettingsStore.boolValue(raw.autoRemoveInvalidAfterTest, base.autoRemoveInvalidAfterTest)
    };
  }

  private static copy(settings: AppSettings): AppSettings {
    return JSON.parse(JSON.stringify(settings)) as AppSettings;
  }

  private static boolValue(value: boolean | undefined, fallback: boolean): boolean {
    return value === undefined ? fallback : value;
  }

  private static stringValue(value: string | undefined, fallback: string): string {
    return value === undefined ? fallback : value;
  }

  private static numberValue(value: number | undefined, fallback: number): number {
    if (value === undefined || Number.isNaN(value)) {
      return fallback;
    }
    return Math.floor(value);
  }

  private static portValue(value: number | undefined, fallback: number): number {
    const port = SettingsStore.numberValue(value, fallback);
    if (port < 1 || port > 65535) {
      return fallback;
    }
    return port;
  }

  private static trafficModeValue(value: string | undefined, fallback: string): string {
    if (value === 'global' || value === 'rules' || value === 'direct') {
      return value;
    }
    return fallback;
  }

  private static arrayValue(value: string[] | undefined, fallback: string[]): string[] {
    return Array.isArray(value) ? value : fallback;
  }

  private static routingRulesValue(value: Array<RoutingRule> | undefined): Array<RoutingRule> {
    if (!Array.isArray(value)) {
      return [];
    }
    const rules = new Array<RoutingRule>();
    for (let index = 0; index < value.length; index++) {
      const item = value[index];
      const rule: RoutingRule = {
        id: SettingsStore.nonEmptyString(item.id, `routing-rule-${index + 1}`),
        remarks: SettingsStore.stringValue(item.remarks, '').trim(),
        domain: SettingsStore.cleanStringArray(item.domain),
        ip: SettingsStore.cleanStringArray(item.ip),
        process: SettingsStore.cleanStringArray(item.process),
        outboundTag: SettingsStore.outboundTagValue(item.outboundTag),
        port: SettingsStore.stringValue(item.port, '').trim(),
        network: SettingsStore.networkValue(item.network),
        protocol: SettingsStore.cleanStringArray(item.protocol),
        enabled: SettingsStore.boolValue(item.enabled, true),
        locked: SettingsStore.boolValue(item.locked, false)
      };
      if (rule.remarks.length > 0 || SettingsStore.hasRoutingMatcher(rule)) {
        rules.push(rule);
      }
    }
    return rules;
  }

  private static cleanStringArray(value: string[] | undefined): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const result = new Array<string>();
    for (let index = 0; index < value.length; index++) {
      const item = value[index].trim();
      if (item.length > 0 && result.indexOf(item) < 0) {
        result.push(item);
      }
    }
    return result;
  }

  private static nonEmptyString(value: string | undefined, fallback: string): string {
    const normalized = SettingsStore.stringValue(value, '').trim();
    return normalized.length > 0 ? normalized : fallback;
  }

  private static outboundTagValue(value: string | undefined): string {
    const normalized = SettingsStore.stringValue(value, 'proxy').trim();
    if (normalized === 'direct' || normalized === 'block' || normalized === 'proxy') {
      return normalized;
    }
    return 'proxy';
  }

  private static networkValue(value: string | undefined): string {
    const normalized = SettingsStore.stringValue(value, '').trim().toLowerCase();
    if (normalized === 'tcp' || normalized === 'udp' || normalized === 'tcp,udp' || normalized === 'udp,tcp') {
      return normalized === 'udp,tcp' ? 'tcp,udp' : normalized;
    }
    return '';
  }

  private static hasRoutingMatcher(rule: RoutingRule): boolean {
    return rule.domain.length > 0 || rule.ip.length > 0 || rule.process.length > 0 ||
      rule.port.length > 0 || rule.protocol.length > 0 || rule.network.length > 0;
  }
}
