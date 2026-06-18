export const DEFAULT_PROFILE_ID: string = 'default-profile';

export type XrayConfigType = 'outbound' | 'full' | 'proxy-chain' | 'policy-group';

export interface ProxyProfile {
  id: string;
  name: string;
  outboundJson: string;
  configType?: XrayConfigType;
  updatedAt: number;
}

export interface ProxyNode {
  id: string;
  name: string;
  protocol: string;
  outboundJson: string;
  configType?: XrayConfigType;
  sourceUrl: string;
  rawLink: string;
  updatedAt: number;
  delayMs: number;
  delayTestAt: number;
  delayStatus: string;
}

export interface SubscriptionGroup {
  id: string;
  name: string;
  url: string;
  enabled: boolean;
  selectedNodeId: string;
  nodes: Array<ProxyNode>;
  updatedAt: number;
  userAgent?: string;
  filter?: string;
  allowInsecureUrl?: boolean;
  autoUpdate?: boolean;
  updateIntervalMinutes?: number;
}

export interface SubscriptionProfile {
  url: string;
  selectedNodeId: string;
  nodes: Array<ProxyNode>;
  updatedAt: number;
  selectedGroupId: string;
  groups: Array<SubscriptionGroup>;
}

export interface ValidationResult {
  valid: boolean;
  message: string;
  protocol: string;
  normalizedJson: string;
  configType?: XrayConfigType;
}

export interface GeneratedXrayConfig {
  configJson: string;
  socksHost?: string;
  socksPort?: number;
  httpProxyHost?: string;
  httpProxyPort?: number;
  metricsServer?: string;
}

export type AppLanguage = 'zh' | 'en';

export interface RoutingRule {
  id: string;
  remarks: string;
  domain: string[];
  ip: string[];
  process: string[];
  outboundTag: string;
  port: string;
  network: string;
  protocol: string[];
  enabled: boolean;
  locked: boolean;
}

export interface VpnInterfaceAddressConfig {
  displayName: string;
  ipv4Client: string;
  ipv4Router: string;
  ipv6Client: string;
  ipv6Router: string;
}

export const VPN_INTERFACE_ADDRESS_CONFIGS: Array<VpnInterfaceAddressConfig> = [
  { displayName: '10.10.14.x', ipv4Client: '10.10.14.1', ipv4Router: '10.10.14.2', ipv6Client: 'fc00::10:10:14:1', ipv6Router: 'fc00::10:10:14:2' },
  { displayName: '10.1.0.x', ipv4Client: '10.1.0.1', ipv4Router: '10.1.0.2', ipv6Client: 'fc00::10:1:0:1', ipv6Router: 'fc00::10:1:0:2' },
  { displayName: '10.0.0.x', ipv4Client: '10.0.0.1', ipv4Router: '10.0.0.2', ipv6Client: 'fc00::10:0:0:1', ipv6Router: 'fc00::10:0:0:2' },
  { displayName: '172.31.0.x', ipv4Client: '172.31.0.1', ipv4Router: '172.31.0.2', ipv6Client: 'fc00::172:31:0:1', ipv6Router: 'fc00::172:31:0:2' },
  { displayName: '172.20.0.x', ipv4Client: '172.20.0.1', ipv4Router: '172.20.0.2', ipv6Client: 'fc00::172:20:0:1', ipv6Router: 'fc00::172:20:0:2' },
  { displayName: '172.16.0.x', ipv4Client: '172.16.0.1', ipv4Router: '172.16.0.2', ipv6Client: 'fc00::172:16:0:1', ipv6Router: 'fc00::172:16:0:2' },
  { displayName: '192.168.100.x', ipv4Client: '192.168.100.1', ipv4Router: '192.168.100.2', ipv6Client: 'fc00::192:168:100:1', ipv6Router: 'fc00::192:168:100:2' }
];

export const DEFAULT_VPN_INTERFACE_ADDRESS_INDEX: number = 0;
export const VPN_BYPASS_LAN_FOLLOW_CONFIG: string = '0';
export const VPN_BYPASS_LAN_BYPASS: string = '1';
export const VPN_BYPASS_LAN_PROXY: string = '2';
export const DEFAULT_VPN_BYPASS_LAN: string = VPN_BYPASS_LAN_BYPASS;
export const DEFAULT_VPN_MTU: number = 1400;
export const MIN_VPN_MTU: number = 1280;
export const MAX_VPN_MTU: number = 9000;
export const DEFAULT_REAL_PING_CONCURRENCY: number = 16;
export const MIN_REAL_PING_CONCURRENCY: number = 1;
export const MAX_REAL_PING_CONCURRENCY: number = 128;
export type AppUiModeNight = '0' | '1' | '2';
export const UI_MODE_NIGHT_SYSTEM: AppUiModeNight = '0';
export const UI_MODE_NIGHT_LIGHT: AppUiModeNight = '1';
export const UI_MODE_NIGHT_DARK: AppUiModeNight = '2';

export function normalizeVpnInterfaceAddressIndex(value: number | undefined, fallback: number = DEFAULT_VPN_INTERFACE_ADDRESS_INDEX): number {
  const safeFallback = fallback >= 0 && fallback < VPN_INTERFACE_ADDRESS_CONFIGS.length ? fallback : DEFAULT_VPN_INTERFACE_ADDRESS_INDEX;
  if (value === undefined || Number.isNaN(value)) {
    return safeFallback;
  }
  const index = Math.floor(value);
  if (index < 0 || index >= VPN_INTERFACE_ADDRESS_CONFIGS.length) {
    return safeFallback;
  }
  return index;
}

export function resolveVpnInterfaceAddressConfig(index?: number): VpnInterfaceAddressConfig {
  return VPN_INTERFACE_ADDRESS_CONFIGS[normalizeVpnInterfaceAddressIndex(index)];
}

export function normalizeVpnBypassLanMode(value: string | undefined, fallback: string = DEFAULT_VPN_BYPASS_LAN): string {
  if (value === VPN_BYPASS_LAN_FOLLOW_CONFIG || value === VPN_BYPASS_LAN_BYPASS || value === VPN_BYPASS_LAN_PROXY) {
    return value;
  }
  return fallback === VPN_BYPASS_LAN_FOLLOW_CONFIG || fallback === VPN_BYPASS_LAN_PROXY ? fallback : DEFAULT_VPN_BYPASS_LAN;
}

export function normalizeVpnMtuValue(value: number | undefined, fallback: number = DEFAULT_VPN_MTU): number {
  if (value === undefined || Number.isNaN(value)) {
    return fallback;
  }
  const mtu = Math.floor(value);
  if (mtu < MIN_VPN_MTU) {
    return MIN_VPN_MTU;
  }
  if (mtu > MAX_VPN_MTU) {
    return MAX_VPN_MTU;
  }
  return mtu;
}

export function normalizeRealPingConcurrency(value: number | undefined, fallback: number = DEFAULT_REAL_PING_CONCURRENCY): number {
  const safeFallback = normalizeRealPingConcurrencyFallback(fallback);
  if (value === undefined || Number.isNaN(value)) {
    return safeFallback;
  }
  const concurrency = Math.floor(value);
  if (concurrency < MIN_REAL_PING_CONCURRENCY) {
    return MIN_REAL_PING_CONCURRENCY;
  }
  if (concurrency > MAX_REAL_PING_CONCURRENCY) {
    return MAX_REAL_PING_CONCURRENCY;
  }
  return concurrency;
}

export function normalizeUiModeNight(value: string | undefined, fallback: AppUiModeNight = UI_MODE_NIGHT_SYSTEM): AppUiModeNight {
  if (value === UI_MODE_NIGHT_LIGHT || value === UI_MODE_NIGHT_DARK || value === UI_MODE_NIGHT_SYSTEM) {
    return value;
  }
  return fallback === UI_MODE_NIGHT_LIGHT || fallback === UI_MODE_NIGHT_DARK ? fallback : UI_MODE_NIGHT_SYSTEM;
}

function normalizeRealPingConcurrencyFallback(value: number): number {
  if (Number.isNaN(value)) {
    return DEFAULT_REAL_PING_CONCURRENCY;
  }
  const concurrency = Math.floor(value);
  if (concurrency < MIN_REAL_PING_CONCURRENCY || concurrency > MAX_REAL_PING_CONCURRENCY) {
    return DEFAULT_REAL_PING_CONCURRENCY;
  }
  return concurrency;
}

export interface AppSettings {
  language: AppLanguage;
  uiModeNight: AppUiModeNight;
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
  localSocksPort: number;
  localSocksDynamicPort: boolean;
  localSocksUdpEnabled: boolean;
  localSocksUsername: string;
  localSocksPassword: string;
  muxEnabled: boolean;
  muxConcurrency: number;
  muxXudpConcurrency: number;
  muxXudpQuic: string;
  fragmentEnabled: boolean;
  fragmentPackets: string;
  fragmentLength: string;
  fragmentInterval: string;
  preferIpv6: boolean;
  proxySharingEnabled: boolean;
  allowInsecure: boolean;
  localDnsPort: number;
  vpnInterfaceAddressIndex: number;
  vpnBypassLan: string;
  vpnMtu: number;
  vpnDns: string;
  remoteDns: string;
  domesticDns: string;
  dnsHosts: string;
  delayTestUrl: string;
  realPingConcurrency: number;
  logLevel: string;
  mode: string;
  trafficMode: string;
  routingDomainStrategy: string;
  adBlockEnabled: boolean;
  routingRules: Array<RoutingRule>;
  autoSortAfterTest: boolean;
  autoRemoveInvalidAfterTest: boolean;
}

export interface RuntimeStats {
  uploadBytes: number;
  downloadBytes: number;
  xrayRunning: boolean;
  tunRunning: boolean;
  lastMessage: string;
}

export enum ConnectionStatus {
  IDLE = 'idle',
  STARTING = 'starting',
  RUNNING = 'running',
  STOPPING = 'stopping',
  ERROR = 'error'
}
