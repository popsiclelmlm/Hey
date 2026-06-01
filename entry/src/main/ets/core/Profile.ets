export const DEFAULT_PROFILE_ID: string = 'default-profile';

export interface ProxyProfile {
  id: string;
  name: string;
  outboundJson: string;
  updatedAt: number;
}

export interface ProxyNode {
  id: string;
  name: string;
  protocol: string;
  outboundJson: string;
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
}

export interface GeneratedXrayConfig {
  configJson: string;
  socksHost: string;
  socksPort: number;
}

export type AppLanguage = 'zh' | 'en';

export interface AppSettings {
  language: AppLanguage;
  sniffingEnabled: boolean;
  routeOnlyEnabled: boolean;
  perAppProxyEnabled: boolean;
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
  socksPort: number;
  localDnsPort: number;
  vpnDns: string;
  remoteDns: string;
  domesticDns: string;
  dnsHosts: string;
  delayTestUrl: string;
  logLevel: string;
  mode: string;
  trafficMode: string;
  routingDomainStrategy: string;
}

export interface RuntimeStats {
  uploadBytes: number;
  downloadBytes: number;
  xrayRunning: boolean;
  tun2SocksRunning: boolean;
  lastMessage: string;
}

export enum ConnectionStatus {
  IDLE = 'idle',
  STARTING = 'starting',
  RUNNING = 'running',
  STOPPING = 'stopping',
  ERROR = 'error'
}
