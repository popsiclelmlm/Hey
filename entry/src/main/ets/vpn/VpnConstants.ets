import { vpnExtension } from '@kit.NetworkKit';
import Want from '@ohos.app.ability.Want';
import {
  DEFAULT_VPN_MTU,
  normalizeVpnBypassLanMode,
  normalizeVpnMtuValue,
  resolveVpnInterfaceAddressConfig,
  RoutingRule,
  VPN_BYPASS_LAN_BYPASS,
  VPN_BYPASS_LAN_FOLLOW_CONFIG,
  VPN_BYPASS_LAN_PROXY
} from '../core/Profile';

export const BUNDLE_NAME: string = 'com.lmlm.hey';
export const VPN_ABILITY_NAME: string = 'HeyVpnAbility';
export const VPN_COMMAND_KEY: string = 'command';
export const VPN_COMMAND_STOP: string = 'stop';
export const VPN_MTU: number = DEFAULT_VPN_MTU;
export const TUN_IPV4: string = resolveVpnInterfaceAddressConfig().ipv4Client;
export const TUN_IPV6: string = resolveVpnInterfaceAddressConfig().ipv6Client;
export const VPN_INTERFACE_NAME: string = 'vpn-tun';
export const DEFAULT_VPN_DNS_ADDRESSES: string[] = ['1.1.1.1', '8.8.8.8'];
export const VPN_BYPASS_LAN_IPV4_ROUTES: string[] = [
  '0.0.0.0/5',
  '8.0.0.0/7',
  '11.0.0.0/8',
  '12.0.0.0/6',
  '16.0.0.0/4',
  '32.0.0.0/3',
  '64.0.0.0/2',
  '128.0.0.0/3',
  '160.0.0.0/5',
  '168.0.0.0/6',
  '172.0.0.0/12',
  '172.32.0.0/11',
  '172.64.0.0/10',
  '172.128.0.0/9',
  '173.0.0.0/8',
  '174.0.0.0/7',
  '176.0.0.0/4',
  '192.0.0.0/9',
  '192.128.0.0/11',
  '192.160.0.0/13',
  '192.169.0.0/16',
  '192.170.0.0/15',
  '192.172.0.0/14',
  '192.176.0.0/12',
  '192.192.0.0/10',
  '193.0.0.0/8',
  '194.0.0.0/7',
  '196.0.0.0/6',
  '200.0.0.0/5',
  '208.0.0.0/4',
  '240.0.0.0/4'
];
const ADDRESS_FAMILY_IPV4: number = 1;
const ADDRESS_FAMILY_IPV6: number = 2;

export function createVpnWant(configJson: string): Want {
  return {
    deviceId: '',
    bundleName: BUNDLE_NAME,
    abilityName: VPN_ABILITY_NAME,
    parameters: {
      xrayConfigJson: configJson as Object
    }
  };
}

export function createStopVpnWant(): Want {
  return {
    deviceId: '',
    bundleName: BUNDLE_NAME,
    abilityName: VPN_ABILITY_NAME
  };
}

export function createStopCommandVpnWant(): Want {
  return {
    deviceId: '',
    bundleName: BUNDLE_NAME,
    abilityName: VPN_ABILITY_NAME,
    parameters: {
      command: VPN_COMMAND_STOP as Object
    }
  };
}

export function createDefaultVpnConfig(
  perAppEnabled: boolean,
  bypassMode: boolean,
  appList: string[],
  vpnDns?: string,
  ipv6Enabled?: boolean,
  vpnMtu?: number,
  vpnInterfaceAddressIndex?: number,
  vpnBypassLan?: string,
  routingRules?: Array<RoutingRule>,
  routeOnlyBypassesPrivate?: boolean
): vpnExtension.VpnConfig {
  const selfBundle = BUNDLE_NAME;
  const routeIpv6 = ipv6Enabled === true;
  const addressConfig = resolveVpnInterfaceAddressConfig(vpnInterfaceAddressIndex);
  const bypassLan = resolveVpnBypassLan(vpnBypassLan, routingRules, routeOnlyBypassesPrivate);
  let blockedApps: string[] = [];
  let trustedApps: string[] = [];
  const selectedApps = appList.filter(app => app !== selfBundle);

  if (!perAppEnabled || selectedApps.length === 0) {
    // 默认防回路拦截自己
    blockedApps = [selfBundle];
  } else {
    if (bypassMode) {
      // 绕过所选应用
      blockedApps = [selfBundle, ...selectedApps];
    } else {
      // 仅代理所选应用，需要把自身包名移除以防环路
      trustedApps = selectedApps;
    }
  }

  const addresses: Array<vpnExtension.LinkAddress> = [
    {
      address: {
        address: addressConfig.ipv4Client,
        family: ADDRESS_FAMILY_IPV4
      },
      prefixLength: 30
    }
  ];
  const routes = buildVpnRoutes(bypassLan, routeIpv6);

  if (routeIpv6) {
    addresses.push({
      address: {
        address: addressConfig.ipv6Client,
        family: ADDRESS_FAMILY_IPV6
      },
      prefixLength: 126
    });
  }

  const config: vpnExtension.VpnConfig = {
    addresses,
    routes,
    dnsAddresses: normalizeVpnDnsAddresses(vpnDns),
    mtu: normalizeVpnMtu(vpnMtu),
    isIPv4Accepted: true,
    isIPv6Accepted: routeIpv6
  };

  if (blockedApps.length > 0) {
    config.blockedApplications = blockedApps;
  }
  if (trustedApps.length > 0) {
    config.trustedApplications = trustedApps;
  }

  return config;
}

export function normalizeVpnMtu(vpnMtu?: number): number {
  return normalizeVpnMtuValue(vpnMtu, VPN_MTU);
}

export function resolveVpnBypassLan(
  vpnBypassLan?: string,
  routingRules?: Array<RoutingRule>,
  routeOnlyBypassesPrivate?: boolean
): boolean {
  const mode = normalizeVpnBypassLanMode(vpnBypassLan);
  if (mode === VPN_BYPASS_LAN_BYPASS) {
    return true;
  }
  if (mode === VPN_BYPASS_LAN_PROXY) {
    return false;
  }
  if (mode === VPN_BYPASS_LAN_FOLLOW_CONFIG && routeOnlyBypassesPrivate === true) {
    return true;
  }
  return hasDirectPrivateRoutingRule(routingRules);
}

export function normalizeVpnDnsAddresses(vpnDns?: string): string[] {
  if (vpnDns === undefined || vpnDns.trim().length === 0) {
    return DEFAULT_VPN_DNS_ADDRESSES.slice();
  }

  const parts = vpnDns.split(',');
  const result: string[] = [];
  for (let index = 0; index < parts.length; index++) {
    const address = parts[index].trim();
    if (address.length > 0 && result.indexOf(address) < 0) {
      result.push(address);
    }
  }

  if (result.length === 0) {
    return DEFAULT_VPN_DNS_ADDRESSES.slice();
  }
  return result;
}

function buildVpnRoutes(bypassLan: boolean, ipv6Enabled: boolean): Array<vpnExtension.RouteInfo> {
  const routes = new Array<vpnExtension.RouteInfo>();
  if (bypassLan) {
    for (let index = 0; index < VPN_BYPASS_LAN_IPV4_ROUTES.length; index++) {
      const parts = VPN_BYPASS_LAN_IPV4_ROUTES[index].split('/');
      routes.push(createVpnRoute(parts[0], Number(parts[1]), ADDRESS_FAMILY_IPV4));
    }
    if (ipv6Enabled) {
      routes.push(createVpnRoute('2000::', 3, ADDRESS_FAMILY_IPV6));
      routes.push(createVpnRoute('fc00::', 18, ADDRESS_FAMILY_IPV6));
    }
    return routes;
  }

  routes.push(createVpnRoute('0.0.0.0', 0, ADDRESS_FAMILY_IPV4));
  if (ipv6Enabled) {
    routes.push(createVpnRoute('::', 0, ADDRESS_FAMILY_IPV6));
  }
  return routes;
}

function createVpnRoute(address: string, prefixLength: number, family: number): vpnExtension.RouteInfo {
  const gatewayAddress = family === ADDRESS_FAMILY_IPV6 ? '::' : '0.0.0.0';
  return {
    interface: VPN_INTERFACE_NAME,
    destination: {
      address: {
        address,
        family
      },
      prefixLength
    },
    gateway: {
      address: gatewayAddress,
      family,
      port: 0
    },
    hasGateway: false,
    isDefaultRoute: prefixLength === 0
  };
}

function hasDirectPrivateRoutingRule(routingRules?: Array<RoutingRule>): boolean {
  if (routingRules === undefined) {
    return false;
  }
  for (let index = 0; index < routingRules.length; index++) {
    const rule = routingRules[index];
    if (!rule.enabled || rule.outboundTag !== 'direct') {
      continue;
    }
    if (rule.ip.indexOf('geoip:private') >= 0 || rule.domain.indexOf('geosite:private') >= 0) {
      return true;
    }
  }
  return false;
}
