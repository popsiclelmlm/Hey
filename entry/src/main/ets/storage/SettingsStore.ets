import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DEFAULT_LANGUAGE, normalizeLanguage } from '../core/I18n';
import { AppLanguage, AppSettings } from '../core/Profile';

const PREFERENCES_NAME: string = 'hey_vpn_settings';
const SETTINGS_KEY: string = 'app_settings';

export const DEFAULT_APP_SETTINGS: AppSettings = {
  language: DEFAULT_LANGUAGE,
  sniffingEnabled: true,
  routeOnlyEnabled: false,
  perAppProxyEnabled: false,
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
  socksPort: 10808,
  localDnsPort: 10853,
  vpnDns: '1.1.1.1',
  remoteDns: '1.1.1.1',
  domesticDns: '223.5.5.5',
  dnsHosts: '',
  delayTestUrl: 'https://www.gstatic.com/generate_204',
  logLevel: 'warning',
  mode: 'VPN',
  trafficMode: 'rules',
  routingDomainStrategy: 'AsIs'
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
      socksPort: SettingsStore.portValue(raw.socksPort, base.socksPort),
      localDnsPort: SettingsStore.portValue(raw.localDnsPort, base.localDnsPort),
      vpnDns: SettingsStore.stringValue(raw.vpnDns, base.vpnDns),
      remoteDns: SettingsStore.stringValue(raw.remoteDns, base.remoteDns),
      domesticDns: SettingsStore.stringValue(raw.domesticDns, base.domesticDns),
      dnsHosts: SettingsStore.stringValue(raw.dnsHosts, base.dnsHosts),
      delayTestUrl: SettingsStore.stringValue(raw.delayTestUrl, base.delayTestUrl),
      logLevel: SettingsStore.stringValue(raw.logLevel, base.logLevel),
      mode: SettingsStore.stringValue(raw.mode, base.mode),
      trafficMode: SettingsStore.trafficModeValue(raw.trafficMode, base.trafficMode),
      routingDomainStrategy: SettingsStore.stringValue(raw.routingDomainStrategy, base.routingDomainStrategy)
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
}
