import { common } from '@kit.AbilityKit';
import { AppLanguage, AppSettings, normalizeVpnMtuValue, RoutingRule } from '../../core/Profile';
import { DEFAULT_APP_SETTINGS, SettingsStore } from '../../storage/SettingsStore';

export interface SettingsDraft {
  language: AppLanguage;
  sniffingEnabled: boolean;
  routeOnlyEnabled: boolean;
  perAppProxyEnabled: boolean;
  perAppProxyList: string[];
  perAppProxyBypass: boolean;
  localDnsEnabled: boolean;
  fakeDnsEnabled: boolean;
  appendHttpProxy: boolean;
  muxEnabled: boolean;
  fragmentEnabled: boolean;
  preferIpv6: boolean;
  proxySharingEnabled: boolean;
  allowInsecure: boolean;
  remoteDns: string;
  domesticDns: string;
  vpnMtu: string;
  vpnDns: string;
  logLevel: string;
  delayTestUrl: string;
  trafficMode: string;
  routingDomainStrategy: string;
  adBlockEnabled: boolean;
  routingRules: Array<RoutingRule>;
  autoSortAfterTest: boolean;
  autoRemoveInvalidAfterTest: boolean;
}

export class SettingsController {
  async load(context: common.Context): Promise<AppSettings> {
    return SettingsStore.load(context);
  }

  async save(context: common.Context, draft: SettingsDraft): Promise<AppSettings> {
    return SettingsStore.save(context, this.buildSettings(draft));
  }

  toDraft(settings: AppSettings): SettingsDraft {
    return {
      language: settings.language,
      sniffingEnabled: settings.sniffingEnabled,
      routeOnlyEnabled: settings.routeOnlyEnabled,
      perAppProxyEnabled: settings.perAppProxyEnabled,
      perAppProxyList: settings.perAppProxyList ?? [],
      perAppProxyBypass: settings.perAppProxyBypass ?? true,
      localDnsEnabled: settings.localDnsEnabled,
      fakeDnsEnabled: settings.fakeDnsEnabled,
      appendHttpProxy: settings.appendHttpProxy,
      muxEnabled: settings.muxEnabled,
      fragmentEnabled: settings.fragmentEnabled,
      preferIpv6: settings.preferIpv6,
      proxySharingEnabled: settings.proxySharingEnabled,
      allowInsecure: settings.allowInsecure,
      remoteDns: settings.remoteDns,
      domesticDns: settings.domesticDns,
      vpnMtu: settings.vpnMtu.toString(),
      vpnDns: settings.vpnDns,
      logLevel: settings.logLevel,
      delayTestUrl: settings.delayTestUrl,
      trafficMode: settings.trafficMode,
      routingDomainStrategy: settings.routingDomainStrategy,
      adBlockEnabled: settings.adBlockEnabled,
      routingRules: this.copyRoutingRules(settings.routingRules),
      autoSortAfterTest: settings.autoSortAfterTest,
      autoRemoveInvalidAfterTest: settings.autoRemoveInvalidAfterTest
    };
  }

  buildSettings(draft: SettingsDraft): AppSettings {
    return {
      language: draft.language,
      sniffingEnabled: draft.sniffingEnabled,
      routeOnlyEnabled: draft.routeOnlyEnabled,
      perAppProxyEnabled: draft.perAppProxyEnabled,
      perAppProxyList: draft.perAppProxyList,
      perAppProxyBypass: draft.perAppProxyBypass,
      localDnsEnabled: draft.localDnsEnabled,
      fakeDnsEnabled: draft.fakeDnsEnabled,
      appendHttpProxy: draft.appendHttpProxy,
      muxEnabled: draft.muxEnabled,
      muxConcurrency: DEFAULT_APP_SETTINGS.muxConcurrency,
      muxXudpConcurrency: DEFAULT_APP_SETTINGS.muxXudpConcurrency,
      muxXudpQuic: DEFAULT_APP_SETTINGS.muxXudpQuic,
      fragmentEnabled: draft.fragmentEnabled,
      fragmentPackets: DEFAULT_APP_SETTINGS.fragmentPackets,
      fragmentLength: DEFAULT_APP_SETTINGS.fragmentLength,
      fragmentInterval: DEFAULT_APP_SETTINGS.fragmentInterval,
      preferIpv6: draft.preferIpv6,
      proxySharingEnabled: draft.proxySharingEnabled,
      allowInsecure: draft.allowInsecure,
      localDnsPort: DEFAULT_APP_SETTINGS.localDnsPort,
      vpnMtu: this.vpnMtuValue(draft.vpnMtu, DEFAULT_APP_SETTINGS.vpnMtu),
      vpnDns: draft.vpnDns.trim(),
      remoteDns: draft.remoteDns.trim(),
      domesticDns: draft.domesticDns.trim(),
      dnsHosts: DEFAULT_APP_SETTINGS.dnsHosts,
      delayTestUrl: draft.delayTestUrl.trim(),
      logLevel: draft.logLevel.trim().length > 0 ? draft.logLevel.trim() : DEFAULT_APP_SETTINGS.logLevel,
      mode: DEFAULT_APP_SETTINGS.mode,
      trafficMode: draft.trafficMode,
      routingDomainStrategy: draft.routingDomainStrategy,
      adBlockEnabled: draft.adBlockEnabled,
      routingRules: this.copyRoutingRules(draft.routingRules),
      autoSortAfterTest: draft.autoSortAfterTest,
      autoRemoveInvalidAfterTest: draft.autoRemoveInvalidAfterTest
    };
  }

  private copyRoutingRules(rules: Array<RoutingRule>): Array<RoutingRule> {
    const result = new Array<RoutingRule>();
    for (let index = 0; index < rules.length; index++) {
      const item = rules[index];
      result.push({
        id: item.id,
        remarks: item.remarks,
        domain: item.domain.slice(),
        ip: item.ip.slice(),
        process: item.process.slice(),
        outboundTag: item.outboundTag,
        port: item.port,
        network: item.network,
        protocol: item.protocol.slice(),
        enabled: item.enabled,
        locked: item.locked
      });
    }
    return result;
  }

  private vpnMtuValue(value: string, fallback: number): number {
    const normalized = value.trim();
    if (normalized.length === 0) {
      return fallback;
    }
    const parsed = Number(normalized);
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return normalizeVpnMtuValue(parsed, fallback);
  }

}

export const SETTINGS_CONTROLLER: SettingsController = new SettingsController();
