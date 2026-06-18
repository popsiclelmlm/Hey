import { common } from '@kit.AbilityKit';
import { AppLanguage, AppSettings, normalizeRealPingConcurrency, normalizeUiModeNight, normalizeVpnBypassLanMode, normalizeVpnInterfaceAddressIndex, normalizeVpnMtuValue, RoutingRule } from '../../core/Profile';
import { DEFAULT_APP_SETTINGS, SettingsStore } from '../../storage/SettingsStore';

export interface SettingsDraft {
  language: AppLanguage;
  uiModeNight: string;
  speedEnabled: boolean;
  confirmRemove: boolean;
  startScanImmediate: boolean;
  groupAllDisplay: boolean;
  doubleColumnDisplay: boolean;
  sniffingEnabled: boolean;
  routeOnlyEnabled: boolean;
  perAppProxyEnabled: boolean;
  perAppProxyList: string[];
  perAppProxyBypass: boolean;
  localDnsEnabled: boolean;
  fakeDnsEnabled: boolean;
  appendHttpProxy: boolean;
  localSocksEnabled: boolean;
  localSocksPort: string;
  localSocksDynamicPort: boolean;
  localSocksUdpEnabled: boolean;
  localSocksUsername: string;
  localSocksPassword: string;
  muxEnabled: boolean;
  muxConcurrency: string;
  muxXudpConcurrency: string;
  muxXudpQuic: string;
  fragmentEnabled: boolean;
  fragmentPackets: string;
  fragmentLength: string;
  fragmentInterval: string;
  preferIpv6: boolean;
  proxySharingEnabled: boolean;
  allowInsecure: boolean;
  remoteDns: string;
  domesticDns: string;
  dnsHosts: string;
  localDnsPort: string;
  vpnInterfaceAddressIndex: number;
  vpnBypassLan: string;
  vpnMtu: string;
  vpnDns: string;
  logLevel: string;
  delayTestUrl: string;
  realPingConcurrency: string;
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
      uiModeNight: settings.uiModeNight,
      speedEnabled: settings.speedEnabled,
      confirmRemove: settings.confirmRemove,
      startScanImmediate: settings.startScanImmediate,
      groupAllDisplay: settings.groupAllDisplay,
      doubleColumnDisplay: settings.doubleColumnDisplay,
      sniffingEnabled: settings.sniffingEnabled,
      routeOnlyEnabled: settings.routeOnlyEnabled,
      perAppProxyEnabled: settings.perAppProxyEnabled,
      perAppProxyList: settings.perAppProxyList ?? [],
      perAppProxyBypass: settings.perAppProxyBypass ?? true,
      localDnsEnabled: settings.localDnsEnabled,
      fakeDnsEnabled: settings.fakeDnsEnabled,
      appendHttpProxy: settings.appendHttpProxy,
      localSocksEnabled: settings.localSocksEnabled,
      localSocksPort: settings.localSocksPort.toString(),
      localSocksDynamicPort: settings.localSocksDynamicPort,
      localSocksUdpEnabled: settings.localSocksUdpEnabled,
      localSocksUsername: settings.localSocksUsername,
      localSocksPassword: settings.localSocksPassword,
      muxEnabled: settings.muxEnabled,
      muxConcurrency: settings.muxConcurrency.toString(),
      muxXudpConcurrency: settings.muxXudpConcurrency.toString(),
      muxXudpQuic: settings.muxXudpQuic,
      fragmentEnabled: settings.fragmentEnabled,
      fragmentPackets: settings.fragmentPackets,
      fragmentLength: settings.fragmentLength,
      fragmentInterval: settings.fragmentInterval,
      preferIpv6: settings.preferIpv6,
      proxySharingEnabled: settings.proxySharingEnabled,
      allowInsecure: settings.allowInsecure,
      remoteDns: settings.remoteDns,
      domesticDns: settings.domesticDns,
      dnsHosts: settings.dnsHosts,
      localDnsPort: settings.localDnsPort.toString(),
      vpnInterfaceAddressIndex: settings.vpnInterfaceAddressIndex,
      vpnBypassLan: settings.vpnBypassLan,
      vpnMtu: settings.vpnMtu.toString(),
      vpnDns: settings.vpnDns,
      logLevel: settings.logLevel,
      delayTestUrl: settings.delayTestUrl,
      realPingConcurrency: settings.realPingConcurrency.toString(),
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
      uiModeNight: normalizeUiModeNight(draft.uiModeNight, DEFAULT_APP_SETTINGS.uiModeNight),
      speedEnabled: draft.speedEnabled,
      confirmRemove: draft.confirmRemove,
      startScanImmediate: draft.startScanImmediate,
      groupAllDisplay: draft.groupAllDisplay,
      doubleColumnDisplay: draft.doubleColumnDisplay,
      sniffingEnabled: draft.sniffingEnabled,
      routeOnlyEnabled: draft.routeOnlyEnabled,
      perAppProxyEnabled: draft.perAppProxyEnabled,
      perAppProxyList: draft.perAppProxyList,
      perAppProxyBypass: draft.perAppProxyBypass,
      localDnsEnabled: draft.localDnsEnabled,
      fakeDnsEnabled: draft.fakeDnsEnabled,
      appendHttpProxy: draft.appendHttpProxy,
      localSocksEnabled: draft.localSocksEnabled,
      localSocksPort: this.portValue(draft.localSocksPort, DEFAULT_APP_SETTINGS.localSocksPort),
      localSocksDynamicPort: draft.localSocksDynamicPort,
      localSocksUdpEnabled: draft.localSocksUdpEnabled,
      localSocksUsername: draft.localSocksUsername.trim(),
      localSocksPassword: draft.localSocksPassword.trim(),
      muxEnabled: draft.muxEnabled,
      muxConcurrency: this.positiveIntValue(draft.muxConcurrency, DEFAULT_APP_SETTINGS.muxConcurrency),
      muxXudpConcurrency: this.positiveIntValue(draft.muxXudpConcurrency, DEFAULT_APP_SETTINGS.muxXudpConcurrency),
      muxXudpQuic: this.muxXudpQuicValue(draft.muxXudpQuic, DEFAULT_APP_SETTINGS.muxXudpQuic),
      fragmentEnabled: draft.fragmentEnabled,
      fragmentPackets: this.nonEmptyString(draft.fragmentPackets, DEFAULT_APP_SETTINGS.fragmentPackets),
      fragmentLength: this.nonEmptyString(draft.fragmentLength, DEFAULT_APP_SETTINGS.fragmentLength),
      fragmentInterval: this.nonEmptyString(draft.fragmentInterval, DEFAULT_APP_SETTINGS.fragmentInterval),
      preferIpv6: draft.preferIpv6,
      proxySharingEnabled: draft.proxySharingEnabled,
      allowInsecure: draft.allowInsecure,
      localDnsPort: this.portValue(draft.localDnsPort, DEFAULT_APP_SETTINGS.localDnsPort),
      vpnInterfaceAddressIndex: normalizeVpnInterfaceAddressIndex(draft.vpnInterfaceAddressIndex, DEFAULT_APP_SETTINGS.vpnInterfaceAddressIndex),
      vpnBypassLan: normalizeVpnBypassLanMode(draft.vpnBypassLan, DEFAULT_APP_SETTINGS.vpnBypassLan),
      vpnMtu: this.vpnMtuValue(draft.vpnMtu, DEFAULT_APP_SETTINGS.vpnMtu),
      vpnDns: draft.vpnDns.trim(),
      remoteDns: draft.remoteDns.trim(),
      domesticDns: draft.domesticDns.trim(),
      dnsHosts: draft.dnsHosts.trim(),
      delayTestUrl: draft.delayTestUrl.trim(),
      realPingConcurrency: this.realPingConcurrencyValue(draft.realPingConcurrency, DEFAULT_APP_SETTINGS.realPingConcurrency),
      logLevel: this.logLevelValue(draft.logLevel, DEFAULT_APP_SETTINGS.logLevel),
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

  private portValue(value: string, fallback: number): number {
    const normalized = value.trim();
    if (normalized.length === 0) {
      return fallback;
    }
    const parsed = Number(normalized);
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    const port = Math.floor(parsed);
    if (port < 1 || port > 65535) {
      return fallback;
    }
    return port;
  }

  private positiveIntValue(value: string, fallback: number): number {
    const normalized = value.trim();
    if (normalized.length === 0) {
      return fallback;
    }
    const parsed = Number(normalized);
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    const result = Math.floor(parsed);
    if (result < 1 || result > 1024) {
      return fallback;
    }
    return result;
  }

  private realPingConcurrencyValue(value: string, fallback: number): number {
    const normalized = value.trim();
    if (normalized.length === 0) {
      return fallback;
    }
    const parsed = Number(normalized);
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return normalizeRealPingConcurrency(parsed, fallback);
  }

  private nonEmptyString(value: string, fallback: string): string {
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : fallback;
  }

  private muxXudpQuicValue(value: string, fallback: string): string {
    const normalized = value.trim();
    if (normalized === 'reject' || normalized === 'allow' || normalized === 'skip') {
      return normalized;
    }
    return fallback;
  }

  private logLevelValue(value: string, fallback: string): string {
    const normalized = value.trim();
    if (normalized === 'debug' || normalized === 'info' || normalized === 'warning' ||
      normalized === 'error' || normalized === 'none') {
      return normalized;
    }
    return fallback;
  }

}

export const SETTINGS_CONTROLLER: SettingsController = new SettingsController();
