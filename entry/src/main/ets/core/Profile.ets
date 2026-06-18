export const DEFAULT_PROFILE_ID: string = 'default-profile';

export type XrayConfigType = 'outbound' | 'full';

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

export const DEFAULT_VPN_MTU: number = 1400;
export const MIN_VPN_MTU: number = 1280;
export const MAX_VPN_MTU: number = 9000;

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

export interface AppSettings {
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
  vpnMtu: number;
  vpnDns: string;
  remoteDns: string;
  domesticDns: string;
  dnsHosts: string;
  delayTestUrl: string;
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
