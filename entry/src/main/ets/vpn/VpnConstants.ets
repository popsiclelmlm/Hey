import { vpnExtension } from '@kit.NetworkKit';
import Want from '@ohos.app.ability.Want';
import { DataPlaneCredentials } from '../core/DataPlaneAuth';
import { DNS_VPN, normalizeVpnDnsServers } from '../core/DnsAddresses';
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
export const DEFAULT_VPN_DNS_ADDRESSES: string[] = [DNS_VPN];
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

export const VPN_CORE_TYPE_KEY: string = 'coreType';
export const VPN_DATA_PLANE_USER_KEY: string = 'dataPlaneUser';
export const VPN_DATA_PLANE_PASS_KEY: string = 'dataPlanePass';

// configJson 是当前内核（Xray 或 sing-box）的完整运行配置；coreType 告诉 VPN 扩展
// 该调用哪个内核的 native 生命周期（默认 xray）。credentials 是数据面入站的会话凭据，
// 由 VPN 扩展交给 tun2socks / hev。
export function createVpnWant(configJson: string, coreType?: string, credentials?: DataPlaneCredentials): Want {
  const parameters: Record<string, Object> = {
    xrayConfigJson: configJson as Object,
    coreType: (coreType ?? 'xray') as Object
  };
  if (credentials !== undefined) {
    parameters[VPN_DATA_PLANE_USER_KEY] = credentials.username as Object;
    parameters[VPN_DATA_PLANE_PASS_KEY] = credentials.password as Object;
  }
  return {
    deviceId: '',
    bundleName: BUNDLE_NAME,
    abilityName: VPN_ABILITY_NAME,
    parameters
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
  // 始终接管 v6(不论开关开不开)。配合下方 createVpnRoute 对 v6 用「空 gateway +
  // isDefaultRoute:false」的写法,HarmonyOS 才会把 ::/0 v6 默认路由真正装到 TUN(否则全局 v6 从
  // 物理网卡直出泄漏)。开关语义由核心承担:关=核心 blackhole 丢弃 v6(逼应用回落 IPv4 走节点);
  // 开=核心把 v6 转发到节点(需节点支持 v6)。节点没 v6 就保持开关关。
  const routeIpv6 = true;
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
      prefixLength: 64
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
  return normalizeVpnDnsServers(vpnDns);
}

function buildVpnRoutes(bypassLan: boolean, ipv6Enabled: boolean): Array<vpnExtension.RouteInfo> {
  const routes = new Array<vpnExtension.RouteInfo>();
  if (bypassLan) {
    for (let index = 0; index < VPN_BYPASS_LAN_IPV4_ROUTES.length; index++) {
      const parts = VPN_BYPASS_LAN_IPV4_ROUTES[index].split('/');
      routes.push(createVpnRoute(parts[0], Number(parts[1]), ADDRESS_FAMILY_IPV4));
    }
    if (ipv6Enabled) {
      // 即使在绕过局域网模式,v6 也用完整 ::/0 默认路由(isDefaultRoute=true)。HarmonyOS
      // 对 2000::/3 这类非默认 v6 路由似乎不安装(实测 vpn-tun 上只有连接路由,全局 v6 仍走
      // 物理口泄漏)。v6 没有 v4 那种私网绕过需求,直接全量接管,残余 v6 由核心决定转发/丢弃。
      routes.push(createVpnRoute('::', 0, ADDRESS_FAMILY_IPV6));
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
  if (family === ADDRESS_FAMILY_IPV6) {
    // v6 路由必须用「空 gateway:{address:''} + isDefaultRoute:false」(参考 arror/x4h)。
    // 实测:用 {address:'::',family:2,port:0}+isDefaultRoute:true 时 HarmonyOS 会丢弃 v6 路由,
    // ::/0 装不进 TUN → 全局 v6 从物理口泄漏。改成此写法后 ::/0 才真正生效到 vpn-tun。
    return {
      interface: VPN_INTERFACE_NAME,
      destination: {
        address: {
          address,
          family
        },
        prefixLength
      },
      gateway: { address: '' },
      hasGateway: false,
      isDefaultRoute: false
    };
  }
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
      address: '0.0.0.0',
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
