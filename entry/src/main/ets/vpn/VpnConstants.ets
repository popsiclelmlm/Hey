import { vpnExtension } from '@kit.NetworkKit';
import Want from '@ohos.app.ability.Want';
import { DEFAULT_VPN_MTU, normalizeVpnMtuValue } from '../core/Profile';

export const BUNDLE_NAME: string = 'com.lmlm.hey';
export const VPN_ABILITY_NAME: string = 'HeyVpnAbility';
export const VPN_COMMAND_KEY: string = 'command';
export const VPN_COMMAND_STOP: string = 'stop';
export const VPN_MTU: number = DEFAULT_VPN_MTU;
export const TUN_IPV4: string = '172.19.0.2';
export const TUN_IPV6: string = 'fd00:172:19::2';
export const VPN_INTERFACE_NAME: string = 'vpn-tun';
export const DEFAULT_VPN_DNS_ADDRESSES: string[] = ['1.1.1.1', '8.8.8.8'];
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
  preferIpv6?: boolean,
  vpnMtu?: number
): vpnExtension.VpnConfig {
  const selfBundle = BUNDLE_NAME;
  const ipv6Enabled = preferIpv6 === true;
  let blockedApps: string[] = [];
  let trustedApps: string[] = [];

  if (!perAppEnabled) {
    // 默认防回路拦截自己
    blockedApps = [selfBundle];
  } else {
    if (bypassMode) {
      // 绕过所选应用
      blockedApps = [selfBundle, ...appList];
    } else {
      // 仅代理所选应用，需要把自身包名移除以防环路
      trustedApps = appList.filter(app => app !== selfBundle);
    }
  }

  const addresses: Array<vpnExtension.LinkAddress> = [
    {
      address: {
        address: TUN_IPV4,
        family: ADDRESS_FAMILY_IPV4
      },
      prefixLength: 30
    }
  ];
  const routes: Array<vpnExtension.RouteInfo> = [
    {
      interface: VPN_INTERFACE_NAME,
      destination: {
        address: {
          address: '0.0.0.0',
          family: ADDRESS_FAMILY_IPV4
        },
        prefixLength: 0
      },
      gateway: {
        address: '0.0.0.0',
        family: ADDRESS_FAMILY_IPV4,
        port: 0
      },
      hasGateway: false,
      isDefaultRoute: true
    }
  ];

  if (ipv6Enabled) {
    addresses.push({
      address: {
        address: TUN_IPV6,
        family: ADDRESS_FAMILY_IPV6
      },
      prefixLength: 126
    });
    routes.push({
      interface: VPN_INTERFACE_NAME,
      destination: {
        address: {
          address: '::',
          family: ADDRESS_FAMILY_IPV6
        },
        prefixLength: 0
      },
      gateway: {
        address: '::',
        family: ADDRESS_FAMILY_IPV6,
        port: 0
      },
      hasGateway: false,
      isDefaultRoute: true
    });
  }

  const config: vpnExtension.VpnConfig = {
    addresses,
    routes,
    dnsAddresses: normalizeVpnDnsAddresses(vpnDns),
    mtu: normalizeVpnMtu(vpnMtu),
    isIPv4Accepted: true,
    isIPv6Accepted: ipv6Enabled
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
