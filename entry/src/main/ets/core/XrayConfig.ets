import { bundleManager } from '@kit.AbilityKit';
import { AppSettings, DEFAULT_VPN_MTU, GeneratedXrayConfig, isProxyOnlyRuntimeMode, isVpnRuntimeMode, normalizeRoutingDomainStrategy, normalizeVpnMtuValue, OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS, OUTBOUND_DOMAIN_RESOLVE_NONE, OUTBOUND_DOMAIN_RESOLVE_REPLACE, resolveDelayTestUrl, RoutingRule, ValidationResult, XrayConfigType } from './Profile';
import { isSupportedShareLink, isWireguardConfigFile, parseShareLinkToOutboundJson, parseWireguardConfigToOutboundJson } from './ShareLinkParser';
import { V2RAYNG_DEFAULT_CORE_LOG_LEVEL, normalizeV2rayNgCoreLogLevel, normalizeV2rayNgFragmentPackets, normalizeV2rayNgMuxXudpQuic, normalizeV2rayNgStreamAlpnWithFallback, normalizeV2rayNgXhttpMode } from './V2rayNgOptions';

interface XrayOutbound {
  protocol?: string;
  tag?: string;
  settings?: Object;
  streamSettings?: Object;
  mux?: XrayMuxConfig;
}

interface XrayWireguardSettings {
  address?: Array<string>;
}

interface XrayHysteria2Server {
  address?: string;
  port?: number;
  password?: string;
  sni?: string;
  alpn?: string;
  insecure?: boolean;
  pinSHA256?: string;
  obfsPassword?: string;
  portHopping?: string;
  portHoppingInterval?: string;
  bandwidthDown?: string;
  bandwidthUp?: string;
}

interface XrayHysteria2Settings {
  servers?: Array<XrayHysteria2Server>;
}

interface XrayHysteriaRuntimeSettings {
  address?: string;
  port?: number;
  version: number;
}

interface XrayHysteriaRuntimeHysteriaSettings {
  version: number;
  auth: string;
}

interface XrayHysteriaRuntimeTlsSettings {
  allowInsecure: boolean;
  serverName?: string;
  alpn?: Array<string>;
  pinnedPeerCertSha256?: string;
}

interface XrayLogConfig {
  loglevel: string;
}

interface XrayMuxConfig {
  enabled: boolean;
  concurrency: number;
  xudpConcurrency: number;
  xudpProxyUDP443: string;
}

interface XraySniffingConfig {
  enabled: boolean;
  destOverride: Array<string>;
  routeOnly?: boolean;
}

interface XrayNoiseMaskConfig {
  rand: string;
  delay: string;
}

interface XrayMaskSettingsConfig {
  password?: string;
  packets?: string;
  length?: string;
  delay?: string;
  noise?: Array<XrayNoiseMaskConfig>;
}

interface XrayMaskConfig {
  type: string;
  settings?: XrayMaskSettingsConfig;
}

interface XrayUdpHopConfig {
  ports?: string;
  interval?: string;
}

interface XrayQuicParamsConfig {
  congestion?: string;
  brutalUp?: string;
  brutalDown?: string;
  udpHop?: XrayUdpHopConfig;
}

interface XrayFinalMaskConfig {
  tcp?: Array<XrayMaskConfig>;
  udp?: Array<XrayMaskConfig>;
  quicParams?: XrayQuicParamsConfig;
}

interface XrayHappyEyeballsConfig {
  prioritizeIPv6: boolean;
  interleave: number;
}

interface XrayDnsServerConfig {
  address: string;
  domains?: Array<string>;
  expectIPs?: Array<string>;
  skipFallback?: boolean;
  tag?: string;
}

interface XrayInboundConfig {
  tag: string;
  listen?: string;
  port?: number;
  protocol: string;
  settings: Object;
  sniffing?: XraySniffingConfig;
}

interface XraySocksAccount {
  user: string;
  pass: string;
}

interface XrayDnsConfig {
  servers: Array<string | XrayDnsServerConfig>;
  hosts?: Object;
  tag?: string;
  enableParallelQuery?: boolean;
}

interface DnsHostsParseResult {
  hosts: Record<string, string | Array<string>>;
  value: Object;
  hasHosts: boolean;
}

interface XrayRoutingRule {
  type: string;
  outboundTag?: string;
  balancerTag?: string;
  inboundTag?: Array<string>;
  ip?: Array<string>;
  domain?: Array<string>;
  port?: string;
  process?: Array<string>;
  protocol?: Array<string>;
  network?: string;
}

interface XrayRoutingConfig {
  domainStrategy: string;
  rules: Array<XrayRoutingRule>;
  balancers?: Array<XrayBalancerConfig>;
}

export type RoutingProcessUidResolver = (packageName: string) => string | undefined;

interface XrayMetricsConfig {
  tag: string;
}

interface XrayPolicySystem {
  statsInboundUplink: boolean;
  statsInboundDownlink: boolean;
  statsOutboundUplink: boolean;
  statsOutboundDownlink: boolean;
}

interface XrayPolicyConfig {
  system: XrayPolicySystem;
}

interface XrayBalancerStrategyConfig {
  type: string;
}

interface XrayBalancerConfig {
  tag: string;
  selector: Array<string>;
  strategy: XrayBalancerStrategyConfig;
}

interface XrayObservatoryConfig {
  subjectSelector: Array<string>;
  probeUrl: string;
  probeInterval: string;
  enableConcurrency: boolean;
}

interface XrayBurstPingConfig {
  destination: string;
  interval: string;
  sampling: number;
  timeout: string;
}

interface XrayBurstObservatoryConfig {
  subjectSelector: Array<string>;
  pingConfig: XrayBurstPingConfig;
}

interface XrayFullConfig {
  log: XrayLogConfig;
  dns?: XrayDnsConfig;
  inbounds: Array<XrayInboundConfig>;
  outbounds: Array<XrayOutbound>;
  routing: XrayRoutingConfig;
  stats?: Object;
  fakedns?: Array<Object>;
  metrics?: XrayMetricsConfig;
  policy?: XrayPolicyConfig;
  observatory?: XrayObservatoryConfig;
  burstObservatory?: XrayBurstObservatoryConfig;
}

interface XrayProxyChainConfig {
  outbounds: Array<XrayOutbound>;
  remarks?: string;
  name?: string;
}

interface XrayPolicyGroupConfig {
  outbounds: Array<XrayOutbound>;
  strategy?: string;
  policyGroupType?: string;
  policyGroupSubscriptionId?: string;
  policyGroupFilter?: string;
  remarks?: string;
  name?: string;
  type?: string;
}

interface XrayPolicyGroupRuntime {
  outbounds: Array<XrayOutbound>;
  balancer: XrayBalancerConfig;
  observatory?: XrayObservatoryConfig;
  burstObservatory?: XrayBurstObservatoryConfig;
}

interface XrayRoutingTarget {
  outboundTag?: string;
  balancerTag?: string;
}

class SocksInboundSettings {
  auth: string;
  udp: boolean;
  userLevel: number = 0;
  accounts?: Array<XraySocksAccount>;

  constructor(udp: boolean = true, username: string = '', password: string = '') {
    this.udp = udp;
    if (username.trim().length > 0 && password.trim().length > 0) {
      this.auth = 'password';
      this.accounts = [{
        user: username.trim(),
        pass: password.trim()
      }];
    } else {
      this.auth = 'noauth';
    }
  }
}

class HttpInboundSettings {
  auth: string = 'noauth';
  userLevel: number = 0;
}

class TunInboundSettings {
  name: string = 'vpn-tun';
  mtu: number;
  userLevel: number = 0;

  constructor(mtu: number = DEFAULT_VPN_MTU) {
    this.mtu = normalizeVpnMtuValue(mtu, DEFAULT_VPN_MTU);
  }
}

class DokodemoInboundSettings {
  address: string = '127.0.0.1';
}

class EmptySettings {
}

const SUPPORTED_PROTOCOLS: Array<string> = ['vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http', 'wireguard', 'hysteria2'];

export const DEFAULT_SOCKS_HOST: string = '127.0.0.1';
export const LOCAL_HTTP_PROXY_HOST: string = '127.0.0.1';
export const LOCAL_HTTP_PROXY_LAN_HOST: string = '0.0.0.0';
export const LOCAL_SOCKS_PROXY_PORT: number = 10808;
export const LOCAL_HTTP_PROXY_PORT: number = 10809;
export const DELAY_TEST_SOCKS_PORT: number = 10825;
// Local Xray metrics (expvar) endpoint. The generated VPN config exposes a
// dokodemo inbound on this port routed to the metrics handler so that
// CGoQueryStats can read real per-tag traffic counters from /debug/vars.
export const METRICS_HOST: string = '127.0.0.1';
export const METRICS_PORT: number = 10845;
export const METRICS_SERVER_URL: string = 'http://127.0.0.1:10845/debug/vars';
const METRICS_OUT_TAG: string = 'metrics_out';
const METRICS_IN_TAG: string = 'metrics_in';
const DNS_OUT_TAG: string = 'dns-out';
const DNS_TAG: string = 'dns';
const DOMESTIC_DNS_TAG_PREFIX: string = 'domestic-dns-';
const DEFAULT_WIREGUARD_IPV4_ADDRESS: string = '172.16.0.2/32';
const DEFAULT_LOG_LEVEL: string = V2RAYNG_DEFAULT_CORE_LOG_LEVEL;
const DEFAULT_ROUTING_DOMAIN_STRATEGY: string = 'AsIs';
const GEOSITE_CN_DOMAIN: string = 'geosite:cn';
const GEOIP_CN_EXPECT: string = 'geoip:cn';
const GEOIP_PRIVATE_RULE: string = 'geoip:private';
const GEOIP_ONLY_CN_PRIVATE_DAT: string = 'geoip-only-cn-private.dat';
const GEOIP_CN_ROUTING_EXT: string = 'ext:' + GEOIP_ONLY_CN_PRIVATE_DAT + ':cn';
const GEOIP_PRIVATE_ROUTING_EXT: string = 'ext:' + GEOIP_ONLY_CN_PRIVATE_DAT + ':private';
export const UNIDENTIFIED_PROCESS_PACKAGE: string = '__unknown_app__';
const UNIDENTIFIED_PROCESS_UID: string = '-1';
const DNS_BLOCK_HOST: string = '127.0.0.1';
const DEFAULT_DNS_HOSTS: Record<string, string | Array<string>> = {
  'domain:googleapis.cn': 'googleapis.com',
  'dns.alidns.com': ['223.5.5.5', '223.6.6.6', '2400:3200::1', '2400:3200:baba::1'],
  'one.one.one.one': ['1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001'],
  'dns.cloudflare.com': ['104.16.132.229', '104.16.133.229', '2606:4700::6810:84e5', '2606:4700::6810:85e5'],
  'cloudflare-dns.com': ['104.16.248.249', '104.16.249.249', '2606:4700::6810:f8f9', '2606:4700::6810:f9f9'],
  'dot.pub': ['1.12.12.12', '120.53.53.53'],
  'dns.google': ['8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844'],
  'dns.quad9.net': ['9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9'],
  'common.dot.dns.yandex.net': ['77.88.8.8', '77.88.8.1', '2a02:6b8::feed:0ff', '2a02:6b8:0:1::feed:0ff']
};
const PROCESS_UID_CACHE: Record<string, string> = {};

function isSupportedProtocol(protocol: string): boolean {
  return SUPPORTED_PROTOCOLS.indexOf(protocol.toLowerCase()) >= 0;
}

function parseOutbound(outboundJson: string): XrayOutbound {
  return JSON.parse(outboundJson) as XrayOutbound;
}

function parseFullConfig(configJson: string): XrayFullConfig {
  return JSON.parse(configJson) as XrayFullConfig;
}

export function validateOutboundJson(outboundJson: string): ValidationResult {
  const trimmed = outboundJson.trim();
  if (trimmed.length === 0) {
    return {
      valid: false,
      message: '请先粘贴 Xray outbound JSON。',
      protocol: '',
      normalizedJson: '',
      configType: 'outbound'
    };
  }

  try {
    const outbound = parseOutbound(trimmed);
    return validateOutboundObject(outbound);
  } catch (error) {
    return {
      valid: false,
      message: `JSON 解析失败：${JSON.stringify(error)}`,
      protocol: '',
      normalizedJson: '',
      configType: 'outbound'
    };
  }
}

export function validateFullConfigJson(configJson: string): ValidationResult {
  const trimmed = configJson.trim();
  if (trimmed.length === 0) {
    return {
      valid: false,
      message: '请先粘贴 Xray 完整配置 JSON。',
      protocol: 'custom',
      normalizedJson: '',
      configType: 'full'
    };
  }

  try {
    const config = parseFullConfig(trimmed);
    return validateFullConfigObject(config);
  } catch (error) {
    return {
      valid: false,
      message: `JSON 解析失败：${JSON.stringify(error)}`,
      protocol: 'custom',
      normalizedJson: '',
      configType: 'full'
    };
  }
}

export function validateProxyChainConfigJson(configJson: string): ValidationResult {
  const trimmed = configJson.trim();
  if (trimmed.length === 0) {
    return {
      valid: false,
      message: '请先粘贴代理链 JSON。',
      protocol: 'proxy-chain',
      normalizedJson: '',
      configType: 'proxy-chain'
    };
  }

  try {
    const config = parseProxyChainConfig(trimmed);
    return validateProxyChainConfigObject(config);
  } catch (error) {
    return {
      valid: false,
      message: `JSON 解析失败：${JSON.stringify(error)}`,
      protocol: 'proxy-chain',
      normalizedJson: '',
      configType: 'proxy-chain'
    };
  }
}

export function validatePolicyGroupConfigJson(configJson: string): ValidationResult {
  const trimmed = configJson.trim();
  if (trimmed.length === 0) {
    return {
      valid: false,
      message: '请先粘贴策略组 JSON。',
      protocol: 'policy-group',
      normalizedJson: '',
      configType: 'policy-group'
    };
  }

  try {
    const config = parsePolicyGroupConfig(trimmed);
    return validatePolicyGroupConfigObject(config);
  } catch (error) {
    return {
      valid: false,
      message: `JSON 解析失败：${JSON.stringify(error)}`,
      protocol: 'policy-group',
      normalizedJson: '',
      configType: 'policy-group'
    };
  }
}

export function normalizeConfigInput(input: string, preferredType?: XrayConfigType): ValidationResult {
  const trimmed = input.trim();
  if (preferredType === 'full') {
    return validateFullConfigJson(trimmed);
  }
  if (preferredType === 'proxy-chain') {
    return validateProxyChainConfigJson(trimmed);
  }
  if (preferredType === 'policy-group') {
    return validatePolicyGroupConfigJson(trimmed);
  }

  if (isWireguardConfigFile(trimmed)) {
    const imported = parseWireguardConfigToOutboundJson(trimmed);
    if (!imported.success) {
      return {
        valid: false,
        message: imported.message,
        protocol: imported.protocol,
        normalizedJson: '',
        configType: 'outbound'
      };
    }
    const validation = validateOutboundJson(imported.outboundJson);
    if (!validation.valid) {
      return validation;
    }
    return {
      valid: true,
      message: imported.message,
      protocol: validation.protocol,
      normalizedJson: validation.normalizedJson,
      configType: 'outbound'
    };
  }

  if (!isSupportedShareLink(trimmed)) {
    return validateJsonConfigInput(trimmed, preferredType);
  }

  const imported = parseShareLinkToOutboundJson(trimmed);
  if (!imported.success) {
    return {
      valid: false,
      message: imported.message,
      protocol: imported.protocol,
      normalizedJson: '',
      configType: 'outbound'
    };
  }

  const validation = validateOutboundJson(imported.outboundJson);
  if (!validation.valid) {
    return validation;
  }

  return {
    valid: true,
    message: imported.message,
    protocol: validation.protocol,
    normalizedJson: validation.normalizedJson,
    configType: 'outbound'
  };
}

export function normalizeOutboundInput(input: string): ValidationResult {
  return normalizeConfigInput(input);
}

function validateJsonConfigInput(input: string, preferredType?: XrayConfigType): ValidationResult {
  if (input.trim().length === 0) {
    return validateOutboundJson(input);
  }

  if (preferredType === 'outbound') {
    return validateOutboundJson(input);
  }

  try {
    const parsed = JSON.parse(input) as Object;
    if (isPolicyGroupCandidate(parsed)) {
      const policyGroup = normalizePolicyGroupConfigObject(parsed);
      if (policyGroup !== null) {
        return validatePolicyGroupConfigObject(policyGroup);
      }
    }
    if (isProxyChainCandidate(parsed)) {
      const proxyChain = normalizeProxyChainConfigObject(parsed);
      if (proxyChain !== null) {
        return validateProxyChainConfigObject(proxyChain);
      }
    }
    if (isFullConfigCandidate(parsed)) {
      return validateFullConfigObject(parsed as XrayFullConfig);
    }
    return validateOutboundObject(parsed as XrayOutbound);
  } catch (error) {
    return {
      valid: false,
      message: `JSON 解析失败：${JSON.stringify(error)}`,
      protocol: '',
      normalizedJson: '',
      configType: preferredType ?? 'outbound'
    };
  }
}

function validatePolicyGroupConfigObject(config: XrayPolicyGroupConfig): ValidationResult {
  if (!Array.isArray(config.outbounds)) {
    return {
      valid: false,
      message: '策略组配置缺少 outbounds 数组。',
      protocol: 'policy-group',
      normalizedJson: '',
      configType: 'policy-group'
    };
  }

  if (config.outbounds.length === 0) {
    return {
      valid: false,
      message: '策略组至少需要一个 outbound。',
      protocol: 'policy-group',
      normalizedJson: '',
      configType: 'policy-group'
    };
  }

  for (let index = 0; index < config.outbounds.length; index++) {
    const validation = validateOutboundObject(config.outbounds[index]);
    if (!validation.valid) {
      return {
        valid: false,
        message: `策略组第 ${index + 1} 个成员无效：${validation.message}`,
        protocol: 'policy-group',
        normalizedJson: '',
        configType: 'policy-group'
      };
    }
  }

  return {
    valid: true,
    message: '策略组配置校验通过。',
    protocol: 'policy-group',
    normalizedJson: JSON.stringify(normalizePolicyGroupConfigForStorage(config), null, 2),
    configType: 'policy-group'
  };
}

function parsePolicyGroupConfig(configJson: string): XrayPolicyGroupConfig {
  const parsed = JSON.parse(configJson) as Object;
  const config = normalizePolicyGroupConfigObject(parsed);
  if (config === null) {
    return {
      outbounds: []
    };
  }
  return config;
}

function normalizePolicyGroupConfigObject(value: Object): XrayPolicyGroupConfig | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, Object>;
  if (!Array.isArray(record['outbounds'])) {
    return null;
  }
  const config: XrayPolicyGroupConfig = {
    outbounds: record['outbounds'] as Array<XrayOutbound>
  };
  if (typeof record['strategy'] === 'string') {
    config.strategy = record['strategy'] as string;
  }
  if (typeof record['policyGroupType'] === 'string') {
    config.policyGroupType = record['policyGroupType'] as string;
  }
  if (typeof record['policyGroupSubscriptionId'] === 'string') {
    config.policyGroupSubscriptionId = record['policyGroupSubscriptionId'] as string;
  }
  if (typeof record['policyGroupFilter'] === 'string') {
    config.policyGroupFilter = record['policyGroupFilter'] as string;
  }
  if (typeof record['remarks'] === 'string') {
    config.remarks = record['remarks'] as string;
  }
  if (typeof record['name'] === 'string') {
    config.name = record['name'] as string;
  }
  if (typeof record['type'] === 'string') {
    config.type = record['type'] as string;
  }
  return config;
}

function normalizePolicyGroupConfigForStorage(config: XrayPolicyGroupConfig): XrayPolicyGroupConfig {
  const normalized: XrayPolicyGroupConfig = {
    outbounds: config.outbounds,
    strategy: normalizePolicyGroupStrategy(config.strategy ?? config.policyGroupType)
  };
  if (config.remarks !== undefined) {
    normalized.remarks = config.remarks;
  }
  if (config.name !== undefined) {
    normalized.name = config.name;
  }
  if (config.policyGroupSubscriptionId !== undefined) {
    normalized.policyGroupSubscriptionId = config.policyGroupSubscriptionId.trim();
  }
  if (config.policyGroupFilter !== undefined) {
    normalized.policyGroupFilter = config.policyGroupFilter.trim();
  }
  normalized.type = 'policy-group';
  return normalized;
}

function isPolicyGroupCandidate(value: Object): boolean {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }
  const record = value as Record<string, Object>;
  if (!Array.isArray(record['outbounds'])) {
    return false;
  }
  const type = typeof record['type'] === 'string' ? (record['type'] as string).toLowerCase() : '';
  const configType = typeof record['configType'] === 'string' ? (record['configType'] as string).toLowerCase() : '';
  return type === 'policy-group' ||
    configType === 'policy-group' ||
    record['strategy'] !== undefined ||
    record['policyGroupType'] !== undefined;
}

function validateProxyChainConfigObject(config: XrayProxyChainConfig): ValidationResult {
  if (!Array.isArray(config.outbounds)) {
    return {
      valid: false,
      message: '代理链配置缺少 outbounds 数组。',
      protocol: 'proxy-chain',
      normalizedJson: '',
      configType: 'proxy-chain'
    };
  }

  if (config.outbounds.length < 2) {
    return {
      valid: false,
      message: '代理链至少需要两个 outbound。',
      protocol: 'proxy-chain',
      normalizedJson: '',
      configType: 'proxy-chain'
    };
  }

  for (let index = 0; index < config.outbounds.length; index++) {
    const validation = validateOutboundObject(config.outbounds[index]);
    if (!validation.valid) {
      return {
        valid: false,
        message: `代理链第 ${index + 1} 跳无效：${validation.message}`,
        protocol: 'proxy-chain',
        normalizedJson: '',
        configType: 'proxy-chain'
      };
    }
  }

  return {
    valid: true,
    message: '代理链配置校验通过。',
    protocol: 'proxy-chain',
    normalizedJson: JSON.stringify(config, null, 2),
    configType: 'proxy-chain'
  };
}

function parseProxyChainConfig(configJson: string): XrayProxyChainConfig {
  const parsed = JSON.parse(configJson) as Object;
  const config = normalizeProxyChainConfigObject(parsed);
  if (config === null) {
    return {
      outbounds: []
    };
  }
  return config;
}

function normalizeProxyChainConfigObject(value: Object): XrayProxyChainConfig | null {
  if (Array.isArray(value)) {
    return {
      outbounds: value as Array<XrayOutbound>
    };
  }
  if (typeof value !== 'object' || value === null) {
    return null;
  }
  const record = value as Record<string, Object>;
  if (!Array.isArray(record['outbounds'])) {
    return null;
  }
  const config: XrayProxyChainConfig = {
    outbounds: record['outbounds'] as Array<XrayOutbound>
  };
  if (typeof record['remarks'] === 'string') {
    config.remarks = record['remarks'] as string;
  }
  if (typeof record['name'] === 'string') {
    config.name = record['name'] as string;
  }
  return config;
}

function isProxyChainCandidate(value: Object): boolean {
  if (Array.isArray(value)) {
    return true;
  }
  if (typeof value !== 'object' || value === null) {
    return false;
  }
  const record = value as Record<string, Object>;
  return Array.isArray(record['outbounds']) &&
    record['inbounds'] === undefined &&
    record['routing'] === undefined &&
    record['dns'] === undefined &&
    record['log'] === undefined;
}

function validateOutboundObject(outbound: XrayOutbound): ValidationResult {
  if (outbound.protocol === undefined || outbound.protocol.trim().length === 0) {
    return {
      valid: false,
      message: 'outbound 缺少 protocol 字段。',
      protocol: '',
      normalizedJson: '',
      configType: 'outbound'
    };
  }

  if (!isSupportedProtocol(outbound.protocol)) {
    return {
      valid: false,
      message: `暂不支持 ${outbound.protocol}，当前支持 VLESS、VMess、Trojan、Shadowsocks、SOCKS、HTTP、WireGuard 和 Hysteria2。`,
      protocol: outbound.protocol,
      normalizedJson: '',
      configType: 'outbound'
    };
  }

  if (outbound.settings === undefined) {
    return {
      valid: false,
      message: 'outbound 缺少 settings 字段。',
      protocol: outbound.protocol,
      normalizedJson: '',
      configType: 'outbound'
    };
  }

  return {
    valid: true,
    message: `${outbound.protocol.toUpperCase()} outbound 校验通过。`,
    protocol: outbound.protocol,
    normalizedJson: JSON.stringify(outbound, null, 2),
    configType: 'outbound'
  };
}

function validateFullConfigObject(config: XrayFullConfig): ValidationResult {
  if (!Array.isArray(config.inbounds)) {
    return {
      valid: false,
      message: '完整配置缺少 inbounds 数组。',
      protocol: 'custom',
      normalizedJson: '',
      configType: 'full'
    };
  }

  if (!Array.isArray(config.outbounds) || config.outbounds.length === 0) {
    return {
      valid: false,
      message: '完整配置缺少 outbounds 数组。',
      protocol: 'custom',
      normalizedJson: '',
      configType: 'full'
    };
  }

  return {
    valid: true,
    message: '完整 Xray 配置校验通过。',
    protocol: 'custom',
    normalizedJson: JSON.stringify(config, null, 2),
    configType: 'full'
  };
}

function isFullConfigCandidate(value: Object): boolean {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }
  const record = value as Record<string, Object>;
  return record['inbounds'] !== undefined ||
    record['outbounds'] !== undefined ||
    record['routing'] !== undefined ||
    record['dns'] !== undefined ||
    record['log'] !== undefined;
}

export function buildXrayConfig(outboundJson: string): GeneratedXrayConfig {
  return buildXrayConfigInternal(outboundJson, undefined);
}

export function buildXrayConfigWithSettings(outboundJson: string, settings: AppSettings): GeneratedXrayConfig {
  return buildXrayConfigInternal(outboundJson, settings);
}

export function buildRuntimeXrayConfig(configJson: string, settings?: AppSettings, configType?: XrayConfigType): GeneratedXrayConfig {
  const validation = normalizeConfigInput(configJson, configType);
  if (!validation.valid) {
    throw new Error(validation.message);
  }

  if (validation.configType === 'full') {
    return {
      configJson: normalizeFullConfigRoutingProcesses(validation.normalizedJson, resolveProcessUid, canUseProcessRouting(settings))
    };
  }
  if (validation.configType === 'proxy-chain') {
    return buildProxyChainXrayConfigInternal(validation.normalizedJson, settings);
  }
  if (validation.configType === 'policy-group') {
    return buildPolicyGroupXrayConfigInternal(validation.normalizedJson, settings);
  }

  return buildXrayConfigInternal(validation.normalizedJson, settings);
}

export function normalizeFullConfigRoutingProcesses(
  configJson: string,
  uidResolver: RoutingProcessUidResolver = resolveProcessUid,
  allowProcessRouting: boolean = true
): string {
  if (!allowProcessRouting) {
    return configJson;
  }
  try {
    const config = parseFullConfig(configJson);
    const routing = config.routing;
    if (routing === undefined || routing === null || !Array.isArray(routing.rules)) {
      return configJson;
    }
    for (let index = 0; index < routing.rules.length; index++) {
      const rule = routing.rules[index];
      if (rule.process === undefined || !Array.isArray(rule.process)) {
        continue;
      }
      const uids = normalizeRoutingRuleProcesses(rule.process, uidResolver);
      if (uids.length > 0) {
        rule.process = uids;
      }
    }
    return JSON.stringify(config, null, 2);
  } catch (error) {
    return configJson;
  }
}

export function collectOutboundDomainPreResolveHosts(configJson: string, settings?: AppSettings, configType?: XrayConfigType): Array<string> {
  if (settings === undefined || settings.outboundDomainResolveMethod === OUTBOUND_DOMAIN_RESOLVE_NONE) {
    return [];
  }
  const validation = normalizeConfigInput(configJson, configType);
  if (!validation.valid || validation.configType === 'full') {
    return [];
  }
  return collectOutboundDomainHosts(preResolveOutbounds(validation.normalizedJson, validation.configType), settings);
}

export function withOutboundDomainResolvedHosts(
  settings: AppSettings | undefined,
  resolvedHosts: Record<string, Array<string>>
): AppSettings | undefined {
  if (settings === undefined) {
    return settings;
  }
  const resolvedKeys = Object.keys(resolvedHosts);
  if (resolvedKeys.length === 0) {
    return settings;
  }

  const parsedHosts = parseDnsHostsValue(settings.dnsHosts);
  const mergedHosts = JSON.parse(JSON.stringify(parsedHosts.hosts)) as Record<string, string | Array<string>>;
  let changed = false;
  for (let index = 0; index < resolvedKeys.length; index++) {
    const host = normalizePreResolveHost(resolvedKeys[index]);
    if (host.length === 0 || resolveStaticHost(host, mergedHosts, settings.preferIpv6).length > 0) {
      continue;
    }
    const addresses = normalizeResolvedDnsAddresses(resolvedHosts[resolvedKeys[index]]);
    if (addresses.length === 0) {
      continue;
    }
    mergedHosts[host.toLowerCase()] = addresses;
    changed = true;
  }
  if (!changed) {
    return settings;
  }

  const runtimeSettings = JSON.parse(JSON.stringify(settings)) as AppSettings;
  runtimeSettings.dnsHosts = JSON.stringify(mergedHosts);
  return runtimeSettings;
}

function buildXrayConfigInternal(outboundJson: string, settings: AppSettings | undefined): GeneratedXrayConfig {
  const validation = validateOutboundJson(outboundJson);
  if (!validation.valid) {
    throw new Error(validation.message);
  }

  const outbound = parseOutbound(validation.normalizedJson);
  if (outbound.tag === undefined || outbound.tag.length === 0) {
    outbound.tag = 'proxy';
  }
  applyOutboundRuntimeSettings(outbound, settings);

  return buildXrayConfigFromOutbounds([outbound], settings);
}

function buildProxyChainXrayConfigInternal(chainJson: string, settings: AppSettings | undefined): GeneratedXrayConfig {
  const validation = validateProxyChainConfigJson(chainJson);
  if (!validation.valid) {
    throw new Error(validation.message);
  }

  const config = parseProxyChainConfig(validation.normalizedJson);
  const outbounds = new Array<XrayOutbound>();
  for (let index = 0; index < config.outbounds.length; index++) {
    const outbound = cloneOutbound(config.outbounds[index]);
    outbound.tag = index === 0 ? 'proxy' : `proxy-chain-${index}`;
    outbounds.push(outbound);
  }
  for (let index = 0; index < outbounds.length - 1; index++) {
    const sockopt = ensureOutboundSockopt(outbounds[index]);
    sockopt['dialerProxy'] = outbounds[index + 1].tag;
  }
  for (let index = 0; index < outbounds.length; index++) {
    applyOutboundRuntimeSettings(outbounds[index], settings);
  }
  return buildXrayConfigFromOutbounds(outbounds, settings);
}

function buildPolicyGroupXrayConfigInternal(groupJson: string, settings: AppSettings | undefined): GeneratedXrayConfig {
  const validation = validatePolicyGroupConfigJson(groupJson);
  if (!validation.valid) {
    throw new Error(validation.message);
  }

  const config = parsePolicyGroupConfig(validation.normalizedJson);
  const runtime = buildPolicyGroupRuntime(config, settings);
  return buildXrayConfigFromOutbounds(runtime.outbounds, settings, runtime.balancer, runtime.observatory, runtime.burstObservatory);
}

function buildPolicyGroupRuntime(config: XrayPolicyGroupConfig, settings: AppSettings | undefined): XrayPolicyGroupRuntime {
  const memberTagPrefix = 'proxy-policy-group-';
  const outbounds = new Array<XrayOutbound>();
  for (let index = 0; index < config.outbounds.length; index++) {
    const outbound = cloneOutbound(config.outbounds[index]);
    outbound.tag = `${memberTagPrefix}${index + 1}`;
    applyOutboundRuntimeSettings(outbound, settings);
    outbounds.push(outbound);
  }

  const strategy = normalizePolicyGroupStrategy(config.strategy ?? config.policyGroupType);
  const balancer: XrayBalancerConfig = {
    tag: 'balancer',
    selector: [memberTagPrefix],
    strategy: {
      type: strategy
    }
  };
  const runtime: XrayPolicyGroupRuntime = {
    outbounds,
    balancer
  };
  const probeUrl = resolvePolicyGroupProbeUrl(settings);
  if (strategy === 'leastPing') {
    runtime.observatory = {
      subjectSelector: [memberTagPrefix],
      probeUrl,
      probeInterval: '3m',
      enableConcurrency: true
    };
  } else if (strategy === 'leastLoad') {
    runtime.burstObservatory = {
      subjectSelector: [memberTagPrefix],
      pingConfig: {
        destination: probeUrl,
        interval: '5m',
        sampling: 2,
        timeout: '30s'
      }
    };
  }
  return runtime;
}

function resolvePolicyGroupProbeUrl(settings: AppSettings | undefined): string {
  return resolveDelayTestUrl(settings?.delayTestUrl);
}

function normalizePolicyGroupStrategy(value: string | undefined): string {
  const normalized = (value ?? '').trim();
  if (normalized === '1' || normalized === 'leastLoad') {
    return 'leastLoad';
  }
  if (normalized === '2' || normalized === 'random') {
    return 'random';
  }
  if (normalized === '3' || normalized === 'roundRobin') {
    return 'roundRobin';
  }
  return 'leastPing';
}

function cloneOutbound(outbound: XrayOutbound): XrayOutbound {
  return JSON.parse(JSON.stringify(outbound)) as XrayOutbound;
}

function applyOutboundRuntimeSettings(outbound: XrayOutbound, settings: AppSettings | undefined): void {
  applyXhttpModeParity(outbound);
  applyTlsServerNameFallbackParity(outbound);
  applyPinnedCertificateAllowInsecureParity(outbound);
  applyWireguardIpv6Setting(outbound, settings);
  applyHysteria2FinalMaskSettings(outbound);
  applyHysteria2RuntimeShape(outbound);
  applyMuxRuntimeSettings(outbound, settings);
  if (settings !== undefined && settings.fragmentEnabled) {
    applyFragmentFinalMaskSettings(outbound, settings);
  }
  if (settings !== undefined && settings.preferIpv6) {
    const sockopt = ensureOutboundSockopt(outbound);
    const happyEyeballs: XrayHappyEyeballsConfig = {
      prioritizeIPv6: true,
      interleave: 2
    };
    sockopt['domainStrategy'] = 'UseIP';
    sockopt['happyEyeballs'] = happyEyeballs;
  }
}

function applyXhttpModeParity(outbound: XrayOutbound): void {
  if (outbound.streamSettings === undefined) {
    return;
  }
  const streamSettings = outbound.streamSettings as Record<string, Object | string | number | boolean | undefined>;
  if (streamSettings['network'] !== 'xhttp') {
    return;
  }
  const settingsValue = streamSettings['xhttpSettings'];
  if (!isRecord(settingsValue)) {
    return;
  }
  const xhttpSettings = settingsValue as Record<string, Object | string | number | boolean | undefined>;
  const mode = xhttpSettings['mode'];
  xhttpSettings['mode'] = normalizeV2rayNgXhttpMode(typeof mode === 'string' ? mode : '');
}

function applyMuxRuntimeSettings(outbound: XrayOutbound, settings: AppSettings | undefined): void {
  if (settings !== undefined && settings.muxEnabled && shouldApplyMux(outbound)) {
    const mux: XrayMuxConfig = {
      enabled: true,
      concurrency: shouldUseVlessFlowMuxConcurrency(outbound) ? -1 : settings.muxConcurrency,
      xudpConcurrency: settings.muxXudpConcurrency,
      xudpProxyUDP443: normalizeV2rayNgMuxXudpQuic(settings.muxXudpQuic)
    };
    outbound.mux = mux;
    return;
  }
  disableExistingMux(outbound);
}

function disableExistingMux(outbound: XrayOutbound): void {
  if (outbound.mux === undefined) {
    return;
  }
  outbound.mux.enabled = false;
  outbound.mux.concurrency = -1;
}

function applyTlsServerNameFallbackParity(outbound: XrayOutbound): void {
  if (outbound.streamSettings === undefined) {
    return;
  }
  const streamSettings = outbound.streamSettings as Record<string, Object | string | number | boolean | undefined>;
  const security = typeof streamSettings['security'] === 'string' ? (streamSettings['security'] as string).toLowerCase() : '';
  const settingsKey = security === 'tls' ? 'tlsSettings' : security === 'reality' ? 'realitySettings' : '';
  if (settingsKey.length === 0 || !isRecord(streamSettings[settingsKey])) {
    return;
  }
  const tlsSettings = streamSettings[settingsKey] as Record<string, Object | string | number | boolean | undefined>;
  const currentServerName = tlsSettings['serverName'];
  if (typeof currentServerName === 'string' && currentServerName.trim().length > 0) {
    return;
  }
  const fallback = resolveTlsServerNameFallback(outbound, streamSettings);
  if (fallback.length > 0) {
    tlsSettings['serverName'] = fallback;
  }
}

function resolveTlsServerNameFallback(
  outbound: XrayOutbound,
  streamSettings: Record<string, Object | string | number | boolean | undefined>
): string {
  const transportServerName = resolveTransportServerNameCandidate(streamSettings);
  if (isDomainNameCandidate(transportServerName)) {
    return transportServerName.trim();
  }
  const outboundHost = outboundServerHost(outbound);
  if (isDomainNameCandidate(outboundHost)) {
    return stripHostBrackets(outboundHost.trim());
  }
  return transportServerName.trim();
}

function resolveTransportServerNameCandidate(
  streamSettings: Record<string, Object | string | number | boolean | undefined>
): string {
  const network = typeof streamSettings['network'] === 'string' ? (streamSettings['network'] as string).toLowerCase() : 'tcp';
  if (network === 'ws') {
    return stringRecordValue(streamSettings['wsSettings'], 'host');
  }
  if (network === 'httpupgrade') {
    return stringRecordValue(streamSettings['httpupgradeSettings'], 'host');
  }
  if (network === 'xhttp') {
    return stringRecordValue(streamSettings['xhttpSettings'], 'host');
  }
  if (network === 'h2' || network === 'http') {
    return firstHostValue(stringOrArrayRecordValue(streamSettings['httpSettings'], 'host'));
  }
  if (network === 'grpc') {
    return stringRecordValue(streamSettings['grpcSettings'], 'authority');
  }
  if (network === 'tcp') {
    return resolveTcpHttpHeaderHost(streamSettings['tcpSettings']);
  }
  return '';
}

function resolveTcpHttpHeaderHost(value: Object | string | number | boolean | undefined): string {
  if (!isRecord(value)) {
    return '';
  }
  const tcpSettings = value as Record<string, Object | string | number | boolean | undefined>;
  if (!isRecord(tcpSettings['header'])) {
    return '';
  }
  const header = tcpSettings['header'] as Record<string, Object | string | number | boolean | undefined>;
  if (!isRecord(header['request'])) {
    return '';
  }
  const request = header['request'] as Record<string, Object | string | number | boolean | undefined>;
  if (!isRecord(request['headers'])) {
    return '';
  }
  const headers = request['headers'] as Record<string, Object | string | number | boolean | undefined>;
  return firstHostValue(headers['Host'] ?? headers['host']);
}

function stringRecordValue(value: Object | string | number | boolean | undefined, key: string): string {
  if (!isRecord(value)) {
    return '';
  }
  const record = value as Record<string, Object | string | number | boolean | undefined>;
  const item = record[key];
  return typeof item === 'string' ? item.trim() : '';
}

function stringOrArrayRecordValue(value: Object | string | number | boolean | undefined, key: string): Object | string | number | boolean | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  const record = value as Record<string, Object | string | number | boolean | undefined>;
  return record[key];
}

function firstHostValue(value: Object | string | number | boolean | undefined): string {
  if (typeof value === 'string') {
    return firstCsvHostValue(value);
  }
  if (!Array.isArray(value)) {
    return '';
  }
  const values = value as Array<Object | string | number | boolean>;
  for (let index = 0; index < values.length; index++) {
    const item: Object | string | number | boolean = values[index];
    if (typeof item === 'string' && item.trim().length > 0) {
      return item.trim();
    }
  }
  return '';
}

function firstCsvHostValue(value: string): string {
  const parts = value.split(',');
  for (let index = 0; index < parts.length; index++) {
    const item = parts[index].trim();
    if (item.length > 0) {
      return item;
    }
  }
  return '';
}

function isDomainNameCandidate(value: string): boolean {
  const host = stripHostBrackets(value.trim());
  return host.length > 0 && !isIpLiteral(host) && /^[A-Za-z0-9.-]+$/.test(host);
}

function applyPinnedCertificateAllowInsecureParity(outbound: XrayOutbound): void {
  if (outbound.streamSettings === undefined) {
    return;
  }
  const streamSettings = outbound.streamSettings as Record<string, Object | string | number | boolean | undefined>;
  disableAllowInsecureWhenPinned(streamSettings['tlsSettings']);
  disableAllowInsecureWhenPinned(streamSettings['realitySettings']);
}

function disableAllowInsecureWhenPinned(value: Object | string | number | boolean | undefined): void {
  if (!isRecord(value)) {
    return;
  }
  const settings = value as Record<string, Object | string | number | boolean | undefined>;
  const pinnedPeerCertSha256 = settings['pinnedPeerCertSha256'];
  if (typeof pinnedPeerCertSha256 === 'string' && pinnedPeerCertSha256.trim().length > 0 &&
    settings['allowInsecure'] === true) {
    settings['allowInsecure'] = false;
  }
}

function shouldApplyMux(outbound: XrayOutbound): boolean {
  const protocol = outbound.protocol?.toLowerCase() ?? '';
  if (protocol === 'shadowsocks' || protocol === 'socks' || protocol === 'http' || protocol === 'trojan' ||
    protocol === 'wireguard' || protocol === 'hysteria2' || protocol === 'hysteria') {
    return false;
  }
  const streamSettings = outbound.streamSettings as Record<string, Object | string | number | boolean | undefined> | undefined;
  if (streamSettings !== undefined && streamSettings['network'] === 'xhttp') {
    return false;
  }
  return true;
}

function shouldUseVlessFlowMuxConcurrency(outbound: XrayOutbound): boolean {
  if ((outbound.protocol?.toLowerCase() ?? '') !== 'vless' || outbound.settings === undefined) {
    return false;
  }
  const settings = outbound.settings as Record<string, Object | string | number | boolean | undefined>;
  const vnext = settings['vnext'];
  if (!Array.isArray(vnext) || vnext.length === 0) {
    return false;
  }
  const server = vnext[0] as Record<string, Object | string | number | boolean | undefined>;
  const users = server['users'];
  if (!Array.isArray(users) || users.length === 0) {
    return false;
  }
  const user = users[0] as Record<string, Object | string | number | boolean | undefined>;
  const flow = user['flow'];
  return typeof flow === 'string' && flow.length > 0;
}

function applyFragmentFinalMaskSettings(outbound: XrayOutbound, settings: AppSettings): void {
  if (outbound.streamSettings === undefined) {
    return;
  }
  const streamSettings = outbound.streamSettings as Record<string, Object | string | number | boolean | undefined>;
  const security = typeof streamSettings['security'] === 'string' ? (streamSettings['security'] as string) : '';
  if (security !== 'tls' && security !== 'reality') {
    return;
  }
  if (streamSettings['finalmask'] !== undefined || hasDialerProxy(streamSettings)) {
    return;
  }

  const fragmentSettings: XrayMaskSettingsConfig = {
    packets: normalizeFragmentPackets(security, settings.fragmentPackets),
    length: settings.fragmentLength,
    delay: settings.fragmentInterval
  };
  const fragmentMask: XrayMaskConfig = {
    type: 'fragment',
    settings: fragmentSettings
  };
  const noiseSettings: XrayMaskSettingsConfig = {
    noise: [
      {
        rand: '10-20',
        delay: '10-16'
      }
    ]
  };
  const noiseMask: XrayMaskConfig = {
    type: 'noise',
    settings: noiseSettings
  };
  const finalMask: XrayFinalMaskConfig = {
    tcp: [fragmentMask],
    udp: [noiseMask]
  };
  streamSettings['finalmask'] = finalMask as Object;
  outbound.streamSettings = streamSettings as Object;
}

function normalizeFragmentPackets(security: string, packets: string): string {
  const normalizedPackets = normalizeV2rayNgFragmentPackets(packets);
  if (security === 'reality' && normalizedPackets === 'tlshello') {
    return '1-3';
  }
  if (security === 'tls' && normalizedPackets !== 'tlshello') {
    return 'tlshello';
  }
  return normalizedPackets;
}

function hasDialerProxy(streamSettings: Record<string, Object | string | number | boolean | undefined>): boolean {
  const sockopt = streamSettings['sockopt'];
  if (!isRecord(sockopt)) {
    return false;
  }
  const record = sockopt as Record<string, Object | string | number | boolean | undefined>;
  const dialerProxy = record['dialerProxy'];
  return typeof dialerProxy === 'string' && dialerProxy.length > 0;
}

function applyHysteria2FinalMaskSettings(outbound: XrayOutbound): void {
  const protocol = outbound.protocol?.toLowerCase();
  if ((protocol !== 'hysteria2' && protocol !== 'hysteria') || outbound.settings === undefined) {
    return;
  }

  const hysteriaSettings = outbound.settings as XrayHysteria2Settings;
  const server = hysteriaSettings.servers?.[0];
  if (server === undefined) {
    return;
  }

  const brutalUp = optionalTrim(server.bandwidthUp);
  const brutalDown = optionalTrim(server.bandwidthDown);
  const portHopping = optionalTrim(server.portHopping);
  const obfsPassword = optionalTrim(server.obfsPassword);
  if (brutalUp === undefined && brutalDown === undefined && portHopping === undefined && obfsPassword === undefined) {
    return;
  }

  let streamSettings: Record<string, Object | string | number | boolean | undefined>;
  if (outbound.streamSettings === undefined) {
    streamSettings = {};
  } else {
    streamSettings = outbound.streamSettings as Record<string, Object | string | number | boolean | undefined>;
  }
  const existingFinalMask = streamSettings['finalmask'];
  let finalMask: XrayFinalMaskConfig;
  if (isRecord(existingFinalMask)) {
    finalMask = existingFinalMask as XrayFinalMaskConfig;
  } else {
    finalMask = {};
  }

  if (brutalUp !== undefined || brutalDown !== undefined || portHopping !== undefined) {
    let quicParams: XrayQuicParamsConfig;
    if (finalMask.quicParams === undefined) {
      quicParams = {};
    } else {
      quicParams = finalMask.quicParams;
    }
    if (brutalUp !== undefined) {
      quicParams.brutalUp = brutalUp;
    }
    if (brutalDown !== undefined) {
      quicParams.brutalDown = brutalDown;
    }
    if (brutalUp !== undefined || brutalDown !== undefined) {
      quicParams.congestion = 'brutal';
    }
    if (portHopping !== undefined) {
      const udpHop: XrayUdpHopConfig = {
        ports: portHopping,
        interval: normalizeHysteria2RuntimeHopInterval(server.portHoppingInterval)
      };
      quicParams.udpHop = udpHop;
    }
    finalMask.quicParams = quicParams;
  }

  if (obfsPassword !== undefined) {
    const maskSettings: XrayMaskSettingsConfig = {
      password: obfsPassword
    };
    const mask: XrayMaskConfig = {
      type: 'salamander',
      settings: maskSettings
    };
    finalMask.udp = [mask];
  }

  streamSettings['finalmask'] = finalMask as Object;
  outbound.streamSettings = streamSettings as Object;
}

function applyHysteria2RuntimeShape(outbound: XrayOutbound): void {
  if ((outbound.protocol?.toLowerCase() ?? '') !== 'hysteria2' || outbound.settings === undefined) {
    return;
  }

  const hysteriaSettings = outbound.settings as XrayHysteria2Settings;
  const server = hysteriaSettings.servers?.[0];
  if (server === undefined) {
    return;
  }

  const runtimeSettings: XrayHysteriaRuntimeSettings = {
    version: 2
  };
  if (server.address !== undefined) {
    runtimeSettings.address = server.address;
  }
  if (server.port !== undefined) {
    runtimeSettings.port = server.port;
  }

  let streamSettings: Record<string, Object | string | number | boolean | undefined>;
  if (outbound.streamSettings === undefined) {
    streamSettings = {};
  } else {
    streamSettings = outbound.streamSettings as Record<string, Object | string | number | boolean | undefined>;
  }

  streamSettings['network'] = 'hysteria';
  const hysteriaRuntimeSettings: XrayHysteriaRuntimeHysteriaSettings = {
    version: 2,
    auth: server.password ?? ''
  };
  streamSettings['hysteriaSettings'] = hysteriaRuntimeSettings as Object;
  streamSettings['security'] = 'tls';
  streamSettings['tlsSettings'] = buildHysteria2TlsSettings(server) as Object;

  outbound.protocol = 'hysteria';
  outbound.settings = runtimeSettings as Object;
  outbound.streamSettings = streamSettings as Object;
}

function buildHysteria2TlsSettings(server: XrayHysteria2Server): XrayHysteriaRuntimeTlsSettings {
  const tlsSettings: XrayHysteriaRuntimeTlsSettings = {
    allowInsecure: server.insecure === true
  };

  const explicitSni = optionalTrim(server.sni);
  const serverName = explicitSni ?? (isDomainNameCandidate(server.address ?? '') ? stripHostBrackets((server.address ?? '').trim()) : '');
  if (serverName.length > 0) {
    tlsSettings.serverName = serverName;
  }

  const alpn = parseCsvStrings(normalizeV2rayNgStreamAlpnWithFallback(server.alpn ?? '', 'h3'));
  if (alpn.length > 0) {
    tlsSettings.alpn = alpn;
  }

  const pinnedPeerCertSha256 = optionalTrim(server.pinSHA256);
  if (pinnedPeerCertSha256 !== undefined) {
    tlsSettings.pinnedPeerCertSha256 = pinnedPeerCertSha256;
    tlsSettings.allowInsecure = false;
  }

  return tlsSettings;
}

function normalizeHysteria2RuntimeHopInterval(value: string | undefined): string {
  const rawInterval = optionalTrim(value);
  if (rawInterval === undefined) {
    return '30';
  }
  const singleValue = Number(rawInterval);
  if (!Number.isNaN(singleValue) && Math.floor(singleValue) === singleValue) {
    return singleValue < 5 ? '30' : rawInterval;
  }

  const parts = rawInterval.split('-');
  if (parts.length !== 2) {
    return '30';
  }
  const start = Number(parts[0].trim());
  const end = Number(parts[1].trim());
  if (Number.isNaN(start) || Number.isNaN(end) || Math.floor(start) !== start || Math.floor(end) !== end) {
    return '30';
  }
  const minStart = Math.max(5, start);
  const minEnd = Math.max(minStart, end);
  return `${minStart}-${minEnd}`;
}

function optionalTrim(value: string | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function isRecord(value: Object | string | number | boolean | undefined): boolean {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function applyWireguardIpv6Setting(outbound: XrayOutbound, settings: AppSettings | undefined): void {
  if (settings === undefined || settings.ipv6Enabled || outbound.protocol?.toLowerCase() !== 'wireguard' || outbound.settings === undefined) {
    return;
  }
  const wireguard = outbound.settings as XrayWireguardSettings;
  if (!Array.isArray(wireguard.address)) {
    return;
  }
  const ipv4Addresses = wireguard.address.filter((address: string) => address.indexOf(':') < 0);
  wireguard.address = ipv4Addresses.length > 0 ? ipv4Addresses : [DEFAULT_WIREGUARD_IPV4_ADDRESS];
}

function buildXrayConfigFromOutbounds(
  proxyOutbounds: Array<XrayOutbound>,
  settings: AppSettings | undefined,
  balancer?: XrayBalancerConfig,
  observatory?: XrayObservatoryConfig,
  burstObservatory?: XrayBurstObservatoryConfig
): GeneratedXrayConfig {
  const tunInbound: XrayInboundConfig = {
    tag: 'tun-in',
    protocol: 'tun',
    settings: new TunInboundSettings(settings === undefined ? DEFAULT_VPN_MTU : settings.vpnMtu)
  };
  const sniffing = buildTunSniffing(settings);
  if (sniffing !== undefined) {
    tunInbound.sniffing = sniffing;
  }
  const vpnMode = settings === undefined || isVpnRuntimeMode(settings.mode);
  const proxyOnlyMode = settings !== undefined && isProxyOnlyRuntimeMode(settings.mode);
  const localSocksEnabled = settings !== undefined && (settings.localSocksEnabled || proxyOnlyMode);
  const appendHttpProxy = settings !== undefined && settings.appendHttpProxy && settings.localSocksEnabled;
  const directOutbound: XrayOutbound = {
    tag: 'direct',
    protocol: 'freedom',
    settings: new EmptySettings()
  };
  const blockOutbound: XrayOutbound = {
    tag: 'block',
    protocol: 'blackhole',
    settings: new EmptySettings()
  };
  const speedEnabled = settings?.speedEnabled ?? false;

  const inbounds = new Array<XrayInboundConfig>();
  const proxyInboundTags = new Array<string>();
  if (vpnMode) {
    inbounds.push(tunInbound);
    proxyInboundTags.push('tun-in');
  }
  const outbounds: Array<XrayOutbound> = proxyOutbounds.concat([directOutbound, blockOutbound]);

  const proxyTarget = buildProxyRoutingTarget(balancer?.tag);
  const routingRules = buildRoutingRules(settings, balancer?.tag);

  if (appendHttpProxy) {
    const runtimeSettings = settings as AppSettings;
    const httpInboundTag = 'http-in';
    const httpProxyHost = resolveLocalProxyHost(runtimeSettings);
    const httpInbound: XrayInboundConfig = {
      tag: httpInboundTag,
      listen: httpProxyHost,
      port: LOCAL_HTTP_PROXY_PORT,
      protocol: 'http',
      settings: new HttpInboundSettings()
    };
    if (sniffing !== undefined) {
      httpInbound.sniffing = sniffing;
    }
    const httpProxyRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: [httpInboundTag]
    };
    applyRoutingTarget(httpProxyRule, proxyTarget);
    inbounds.push(httpInbound);
    routingRules.unshift(httpProxyRule);
  }
  if (localSocksEnabled) {
    const runtimeSettings = settings as AppSettings;
    const socksInboundTag = 'socks-in';
    const socksInbound: XrayInboundConfig = {
      tag: socksInboundTag,
      listen: resolveLocalProxyHost(runtimeSettings),
      port: runtimeSettings.localSocksPort,
      protocol: 'socks',
      settings: new SocksInboundSettings(
        runtimeSettings.localSocksUdpEnabled,
        runtimeSettings.localSocksUsername,
        runtimeSettings.localSocksPassword
      )
    };
    if (sniffing !== undefined) {
      socksInbound.sniffing = sniffing;
    }
    const socksProxyRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: [socksInboundTag]
    };
    applyRoutingTarget(socksProxyRule, proxyTarget);
    inbounds.push(socksInbound);
    routingRules.unshift(socksProxyRule);
  }
  appendDefaultProxyBalancerRule(routingRules, balancer?.tag, proxyInboundTags);

  if (settings !== undefined && settings.localDnsEnabled && vpnMode) {
    const dnsOutbound: XrayOutbound = {
      tag: DNS_OUT_TAG,
      protocol: 'dns'
    };
    const dnsRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: ['tun-in'],
      outboundTag: DNS_OUT_TAG,
      port: '53'
    };
    outbounds.push(dnsOutbound);
    routingRules.unshift(dnsRule);
  }
  if (speedEnabled) {
    const metricsInbound: XrayInboundConfig = {
      tag: METRICS_IN_TAG,
      listen: METRICS_HOST,
      port: METRICS_PORT,
      protocol: 'dokodemo-door',
      settings: new DokodemoInboundSettings()
    };
    const metricsRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: [METRICS_IN_TAG],
      outboundTag: METRICS_OUT_TAG
    };
    inbounds.push(metricsInbound);
    // Route the metrics inbound to the metrics handler ahead of any user/traffic
    // rule so the local /debug/vars probe is never proxied or blocked.
    routingRules.unshift(metricsRule);
  }

  const dns = buildDnsConfig(settings);
  applyOutboundDomainResolveSettings(outbounds, dns, settings);
  prependDnsRoutingRules(routingRules, dns, proxyTarget);

  const config: XrayFullConfig = {
    log: {
      loglevel: normalizeV2rayNgCoreLogLevel(settings?.logLevel ?? DEFAULT_LOG_LEVEL, DEFAULT_LOG_LEVEL)
    },
    dns,
    inbounds,
    outbounds,
    routing: {
      domainStrategy: normalizeRoutingDomainStrategy(settings?.routingDomainStrategy, DEFAULT_ROUTING_DOMAIN_STRATEGY),
      rules: routingRules
    }
  };
  if (speedEnabled) {
    const policy: XrayPolicyConfig = {
      system: {
        statsInboundUplink: true,
        statsInboundDownlink: true,
        statsOutboundUplink: true,
        statsOutboundDownlink: true
      }
    };
    config.stats = new EmptySettings();
    config.metrics = {
      tag: METRICS_OUT_TAG
    };
    config.policy = policy;
  }
  if (settings !== undefined && settings.localDnsEnabled && settings.fakeDnsEnabled) {
    config.fakedns = [new EmptySettings()];
  }
  if (balancer !== undefined) {
    config.routing.balancers = [balancer];
  }
  if (observatory !== undefined) {
    config.observatory = observatory;
  }
  if (burstObservatory !== undefined) {
    config.burstObservatory = burstObservatory;
  }

  const runtimeHttpProxyHost = appendHttpProxy ? resolveLocalProxyHost(settings as AppSettings) : undefined;
  const runtimeHttpProxyPort = appendHttpProxy ? LOCAL_HTTP_PROXY_PORT : undefined;
  const runtimeSocksHost = localSocksEnabled ? resolveLocalProxyHost(settings as AppSettings) : undefined;
  const runtimeSocksPort = localSocksEnabled ? (settings as AppSettings).localSocksPort : undefined;

  return {
    configJson: JSON.stringify(config, null, 2),
    socksHost: runtimeSocksHost,
    socksPort: runtimeSocksPort,
    httpProxyHost: runtimeHttpProxyHost,
    httpProxyPort: runtimeHttpProxyPort,
    metricsServer: speedEnabled ? METRICS_SERVER_URL : undefined
  };
}

export function buildDelayTestConfig(outboundJson: string, socksPort: number = DELAY_TEST_SOCKS_PORT): GeneratedXrayConfig {
  const validation = validateOutboundJson(outboundJson);
  if (!validation.valid) {
    throw new Error(validation.message);
  }

  const outbound = parseOutbound(validation.normalizedJson);
  if (outbound.tag === undefined || outbound.tag.length === 0) {
    outbound.tag = 'proxy';
  }
  outbound.mux = undefined;

  const socksInbound: XrayInboundConfig = {
    tag: 'socks-in',
    listen: DEFAULT_SOCKS_HOST,
    port: socksPort,
    protocol: 'socks',
    settings: new SocksInboundSettings()
  };
  const directOutbound: XrayOutbound = {
    tag: 'direct',
    protocol: 'freedom',
    settings: new EmptySettings()
  };
  const blockOutbound: XrayOutbound = {
    tag: 'block',
    protocol: 'blackhole',
    settings: new EmptySettings()
  };

  const config: XrayFullConfig = {
    log: {
      loglevel: 'none'
    },
    inbounds: [socksInbound],
    outbounds: [outbound, directOutbound, blockOutbound],
    routing: {
      domainStrategy: 'AsIs',
      rules: []
    }
  };

  return {
    configJson: JSON.stringify(config),
    socksHost: DEFAULT_SOCKS_HOST,
    socksPort
  };
}

function buildDnsConfig(settings: AppSettings | undefined): XrayDnsConfig {
  if (settings === undefined) {
    const defaultDns: XrayDnsConfig = {
      servers: ['1.1.1.1', '8.8.8.8']
    };
    return defaultDns;
  }
  const remoteDns = parseCsvStrings(settings.remoteDns);
  const domesticDns = parseCsvStrings(settings.domesticDns);
  const servers: Array<string | XrayDnsServerConfig> = [];
  addCsvValues(servers, settings.remoteDns);
  addDnsProxyDomainServer(servers, remoteDns, collectDnsRuleDomains(settings, ['proxy', 'proxy-chain', 'policy-group']));
  addDomesticDnsServers(servers, domesticDns, collectDnsRuleDomains(settings, ['direct']));
  if (servers.length === 0) {
    servers.push('1.1.1.1');
  }
  const dns: XrayDnsConfig = {
    servers,
    tag: DNS_TAG
  };
  if (remoteDns.length + domesticDns.length > 2) {
    dns.enableParallelQuery = true;
  }
  if (settings.localDnsEnabled && settings.fakeDnsEnabled) {
    dns.servers.unshift({
      address: 'fakedns',
      domains: buildFakeDnsDomains(settings)
    });
  }
  applyDnsHosts(dns, settings);
  return dns;
}

function addDnsProxyDomainServer(
  servers: Array<string | XrayDnsServerConfig>,
  remoteDns: Array<string>,
  proxyDomains: Array<string>
): void {
  if (remoteDns.length === 0 || proxyDomains.length === 0) {
    return;
  }
  servers.push({
    address: remoteDns[0],
    domains: proxyDomains
  });
}

function addDomesticDnsServers(
  servers: Array<string | XrayDnsServerConfig>,
  domesticDns: Array<string>,
  directDomains: Array<string>
): void {
  const cnDomains = new Array<string>();
  const regularDomains = new Array<string>();
  for (let index = 0; index < directDomains.length; index++) {
    const domain = directDomains[index];
    if (isCnRegionDnsDomain(domain)) {
      addUniqueString(cnDomains, domain);
    } else {
      addUniqueString(regularDomains, domain);
    }
  }

  for (let index = 0; index < domesticDns.length; index++) {
    const tag = `${DOMESTIC_DNS_TAG_PREFIX}${index}`;
    servers.push({
      address: domesticDns[index],
      domains: regularDomains.slice(),
      skipFallback: true,
      tag
    });
    if (cnDomains.length > 0) {
      servers.push({
        address: domesticDns[index],
        domains: cnDomains.slice(),
        expectIPs: [GEOIP_CN_EXPECT],
        skipFallback: true,
        tag: `${tag}_cn_expect`
      });
    }
  }
}

function applyDnsHosts(dns: XrayDnsConfig, settings: AppSettings): void {
  const hosts: Record<string, string | Array<string>> = {};
  const blockDomains = collectDnsRuleDomains(settings, ['block']);
  for (let index = 0; index < blockDomains.length; index++) {
    hosts[blockDomains[index]] = DNS_BLOCK_HOST;
  }

  applyDefaultDnsHosts(hosts);

  const parsedHosts = settings.dnsHosts.trim().length > 0 ? parseDnsHostsValue(settings.dnsHosts) : undefined;
  if (parsedHosts !== undefined) {
    const userKeys = Object.keys(parsedHosts.hosts);
    for (let index = 0; index < userKeys.length; index++) {
      hosts[userKeys[index]] = parsedHosts.hosts[userKeys[index]];
    }
  }

  if (Object.keys(hosts).length > 0) {
    dns.hosts = hosts as Object;
    return;
  }
  if (parsedHosts !== undefined) {
    dns.hosts = parsedHosts.value;
  }
}

function applyDefaultDnsHosts(hosts: Record<string, string | Array<string>>): void {
  const keys = Object.keys(DEFAULT_DNS_HOSTS);
  for (let index = 0; index < keys.length; index++) {
    const value = DEFAULT_DNS_HOSTS[keys[index]];
    hosts[keys[index]] = Array.isArray(value) ? value.slice() : value;
  }
}

function prependDnsRoutingRules(rules: Array<XrayRoutingRule>, dns: XrayDnsConfig, proxyTarget: XrayRoutingTarget): void {
  const dnsRules = new Array<XrayRoutingRule>();
  const domesticTags = collectDomesticDnsTags(dns);
  if (domesticTags.length > 0) {
    dnsRules.push({
      type: 'field',
      inboundTag: domesticTags,
      outboundTag: 'direct'
    });
  }
  if (dns.tag !== undefined && dns.tag.length > 0) {
    const proxyRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: [dns.tag]
    };
    applyRoutingTarget(proxyRule, proxyTarget);
    dnsRules.push(proxyRule);
  }
  for (let index = dnsRules.length - 1; index >= 0; index--) {
    rules.unshift(dnsRules[index]);
  }
}

function collectDomesticDnsTags(dns: XrayDnsConfig): Array<string> {
  const tags = new Array<string>();
  for (let index = 0; index < dns.servers.length; index++) {
    const server = dns.servers[index];
    if (typeof server === 'string') {
      continue;
    }
    const tag = server.tag ?? '';
    if (tag.startsWith(DOMESTIC_DNS_TAG_PREFIX)) {
      addUniqueString(tags, tag);
    }
  }
  return tags;
}

function collectDnsRuleDomains(settings: AppSettings, outboundTags: Array<string>): Array<string> {
  const domains = new Array<string>();
  for (let index = 0; index < settings.routingRules.length; index++) {
    const rule = settings.routingRules[index];
    if (!rule.enabled || outboundTags.indexOf(rule.outboundTag) < 0) {
      continue;
    }
    addStringArrayValues(domains, rule.domain);
  }
  return domains;
}

function isCnRegionDnsDomain(domain: string): boolean {
  const normalized = domain.trim();
  return normalized === GEOSITE_CN_DOMAIN ||
    (normalized.startsWith('geosite:') && (normalized.endsWith('-cn') || normalized.endsWith('@cn')));
}

function applyOutboundDomainResolveSettings(outbounds: Array<XrayOutbound>, dns: XrayDnsConfig, settings: AppSettings | undefined): void {
  if (settings === undefined || settings.outboundDomainResolveMethod === OUTBOUND_DOMAIN_RESOLVE_NONE) {
    return;
  }
  const parsedHosts = parseDnsHostsValue(settings.dnsHosts);
  if (!parsedHosts.hasHosts) {
    return;
  }
  if (settings.outboundDomainResolveMethod === OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS) {
    mergeDnsHosts(dns, parsedHosts.hosts);
    for (let index = 0; index < outbounds.length; index++) {
      const host = outboundServerHost(outbounds[index]);
      if (host.length > 0 && resolveStaticHost(host, parsedHosts.hosts, settings.preferIpv6).length > 0) {
        applyOutboundUseIp(outbounds[index], settings.preferIpv6);
      }
    }
    return;
  }
  if (settings.outboundDomainResolveMethod === OUTBOUND_DOMAIN_RESOLVE_REPLACE) {
    for (let index = 0; index < outbounds.length; index++) {
      replaceOutboundServerHost(outbounds[index], parsedHosts.hosts, settings.preferIpv6);
    }
  }
}

function parseDnsHostsValue(value: string): DnsHostsParseResult {
  const normalized = value.trim();
  try {
    const parsed = JSON.parse(normalized) as Record<string, string | Array<string>>;
    const hosts = normalizeDnsHostsRecord(parsed);
    return {
      hosts,
      value: hosts as Object,
      hasHosts: Object.keys(hosts).length > 0
    };
  } catch (error) {
    const hosts: Record<string, string | Array<string>> = {};
    const items = normalized.split(',');
    for (let index = 0; index < items.length; index++) {
      const item = items[index].trim();
      const separatorIndex = item.indexOf(':');
      if (separatorIndex <= 0 || separatorIndex >= item.length - 1) {
        continue;
      }
      const domain = item.substring(0, separatorIndex).trim();
      const address = item.substring(separatorIndex + 1).trim();
      if (domain.length === 0 || address.length === 0) {
        continue;
      }
      hosts[domain] = address;
    }
    return {
      hosts,
      value: Object.keys(hosts).length > 0 ? hosts as Object : new EmptySettings(),
      hasHosts: Object.keys(hosts).length > 0
    };
  }
}

function normalizeDnsHostsRecord(parsed: Record<string, string | Array<string>>): Record<string, string | Array<string>> {
  const hosts: Record<string, string | Array<string>> = {};
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return hosts;
  }
  const keys = Object.keys(parsed);
  for (let index = 0; index < keys.length; index++) {
    const key = keys[index].trim();
    const value = parsed[keys[index]];
    if (key.length === 0) {
      continue;
    }
    if (typeof value === 'string' && value.trim().length > 0) {
      hosts[key] = value.trim();
    } else if (Array.isArray(value)) {
      const addresses = new Array<string>();
      for (let valueIndex = 0; valueIndex < value.length; valueIndex++) {
        const address = value[valueIndex];
        if (typeof address === 'string' && address.trim().length > 0) {
          addresses.push(address.trim());
        }
      }
      if (addresses.length > 0) {
        hosts[key] = addresses;
      }
    }
  }
  return hosts;
}

function mergeDnsHosts(dns: XrayDnsConfig, hosts: Record<string, string | Array<string>>): void {
  const current = dns.hosts as Record<string, string | Array<string>> | undefined;
  const next: Record<string, string | Array<string>> = current === undefined ? {} : JSON.parse(JSON.stringify(current)) as Record<string, string | Array<string>>;
  const keys = Object.keys(hosts);
  for (let index = 0; index < keys.length; index++) {
    next[keys[index]] = hosts[keys[index]];
  }
  dns.hosts = next as Object;
}

function preResolveOutbounds(configJson: string, configType?: XrayConfigType): Array<XrayOutbound> {
  if (configType === 'proxy-chain') {
    return parseProxyChainConfig(configJson).outbounds;
  }
  if (configType === 'policy-group') {
    return parsePolicyGroupConfig(configJson).outbounds;
  }
  return [parseOutbound(configJson)];
}

function collectOutboundDomainHosts(outbounds: Array<XrayOutbound>, settings: AppSettings): Array<string> {
  const parsedHosts = parseDnsHostsValue(settings.dnsHosts);
  const seen: Record<string, boolean> = {};
  const hosts = new Array<string>();
  for (let index = 0; index < outbounds.length; index++) {
    const host = normalizePreResolveHost(outboundServerHost(outbounds[index]));
    if (host.length === 0) {
      continue;
    }
    const key = host.toLowerCase();
    if (seen[key] || resolveStaticHost(host, parsedHosts.hosts, settings.preferIpv6).length > 0) {
      continue;
    }
    seen[key] = true;
    hosts.push(key);
  }
  return hosts;
}

function normalizePreResolveHost(host: string): string {
  const normalized = stripHostBrackets(host.trim());
  if (normalized.length === 0 || isIpLiteral(normalized)) {
    return '';
  }
  return normalized;
}

function normalizeResolvedDnsAddresses(values: Array<string>): Array<string> {
  const seen: Record<string, boolean> = {};
  const addresses = new Array<string>();
  for (let index = 0; index < values.length; index++) {
    const address = stripHostBrackets(values[index].trim());
    if (address.length === 0 || seen[address]) {
      continue;
    }
    seen[address] = true;
    addresses.push(address);
  }
  return addresses;
}

function outboundServerHost(outbound: XrayOutbound): string {
  const settings = outbound.settings as Record<string, Object> | undefined;
  if (settings === undefined) {
    return '';
  }
  const vnext = settings['vnext'];
  const vnextAddress = firstServerAddress(vnext);
  if (vnextAddress.length > 0) {
    return vnextAddress;
  }
  const servers = settings['servers'];
  const serverAddress = firstServerAddress(servers);
  if (serverAddress.length > 0) {
    return serverAddress;
  }
  const address = settings['address'];
  if (typeof address === 'string') {
    return address;
  }
  const endpoint = firstWireguardEndpoint(settings['peers']);
  return endpointHost(endpoint);
}

function firstServerAddress(value: Object | undefined): string {
  if (!Array.isArray(value) || value.length === 0) {
    return '';
  }
  const first = value[0] as Record<string, Object>;
  const address = first['address'];
  return typeof address === 'string' ? address : '';
}

function firstWireguardEndpoint(value: Object | undefined): string {
  if (!Array.isArray(value) || value.length === 0) {
    return '';
  }
  const first = value[0] as Record<string, Object>;
  const endpoint = first['endpoint'];
  return typeof endpoint === 'string' ? endpoint : '';
}

function replaceOutboundServerHost(outbound: XrayOutbound, hosts: Record<string, string | Array<string>>, preferIpv6: boolean): void {
  const settings = outbound.settings as Record<string, Object> | undefined;
  if (settings === undefined) {
    return;
  }
  if (replaceFirstServerAddress(settings['vnext'], hosts, preferIpv6)) {
    return;
  }
  if (replaceFirstServerAddress(settings['servers'], hosts, preferIpv6)) {
    return;
  }
  const address = settings['address'];
  if (typeof address === 'string') {
    const resolved = resolveStaticHost(address, hosts, preferIpv6);
    if (resolved.length > 0) {
      settings['address'] = resolved as Object;
    }
    return;
  }
  replaceFirstWireguardEndpoint(settings['peers'], hosts, preferIpv6);
}

function replaceFirstServerAddress(value: Object | undefined, hosts: Record<string, string | Array<string>>, preferIpv6: boolean): boolean {
  if (!Array.isArray(value) || value.length === 0) {
    return false;
  }
  const first = value[0] as Record<string, Object>;
  const address = first['address'];
  if (typeof address !== 'string') {
    return false;
  }
  const resolved = resolveStaticHost(address, hosts, preferIpv6);
  if (resolved.length === 0) {
    return false;
  }
  first['address'] = resolved as Object;
  return true;
}

function replaceFirstWireguardEndpoint(value: Object | undefined, hosts: Record<string, string | Array<string>>, preferIpv6: boolean): void {
  if (!Array.isArray(value) || value.length === 0) {
    return;
  }
  const first = value[0] as Record<string, Object>;
  const endpoint = first['endpoint'];
  if (typeof endpoint !== 'string') {
    return;
  }
  const host = endpointHost(endpoint);
  const resolved = resolveStaticHost(host, hosts, preferIpv6);
  if (resolved.length > 0) {
    first['endpoint'] = replaceEndpointHost(endpoint, resolved) as Object;
  }
}

function resolveStaticHost(host: string, hosts: Record<string, string | Array<string>>, preferIpv6: boolean): string {
  const normalized = stripHostBrackets(host.trim());
  if (normalized.length === 0 || isIpLiteral(normalized)) {
    return '';
  }
  const direct = hosts[normalized] ?? hosts[normalized.toLowerCase()];
  if (direct === undefined) {
    return '';
  }
  return pickResolvedAddress(direct, preferIpv6);
}

function pickResolvedAddress(value: string | Array<string>, preferIpv6: boolean): string {
  if (typeof value === 'string') {
    return value;
  }
  if (value.length === 0) {
    return '';
  }
  for (let index = 0; index < value.length; index++) {
    const address = value[index];
    const isIpv6 = address.indexOf(':') >= 0;
    if ((preferIpv6 && isIpv6) || (!preferIpv6 && !isIpv6)) {
      return address;
    }
  }
  return value[0];
}

function applyOutboundUseIp(outbound: XrayOutbound, preferIpv6: boolean): void {
  const sockopt = ensureOutboundSockopt(outbound);
  const happyEyeballs: XrayHappyEyeballsConfig = {
    prioritizeIPv6: preferIpv6,
    interleave: 2
  };
  sockopt['domainStrategy'] = 'UseIP';
  sockopt['happyEyeballs'] = happyEyeballs;
}

function endpointHost(endpoint: string): string {
  if (endpoint.length === 0) {
    return '';
  }
  if (endpoint.startsWith('[')) {
    const end = endpoint.indexOf(']');
    return end > 0 ? endpoint.substring(1, end) : '';
  }
  const separator = endpoint.lastIndexOf(':');
  return separator > 0 ? endpoint.substring(0, separator) : endpoint;
}

function replaceEndpointHost(endpoint: string, host: string): string {
  if (endpoint.startsWith('[')) {
    const end = endpoint.indexOf(']');
    const suffix = end >= 0 ? endpoint.substring(end + 1) : '';
    return formatEndpointHost(host) + suffix;
  }
  const separator = endpoint.lastIndexOf(':');
  if (separator <= 0) {
    return formatEndpointHost(host);
  }
  return `${formatEndpointHost(host)}${endpoint.substring(separator)}`;
}

function formatEndpointHost(host: string): string {
  return host.indexOf(':') >= 0 ? `[${host}]` : host;
}

function stripHostBrackets(host: string): string {
  if (host.startsWith('[') && host.endsWith(']')) {
    return host.substring(1, host.length - 1);
  }
  return host;
}

function isIpLiteral(host: string): boolean {
  if (host.indexOf(':') >= 0) {
    return true;
  }
  return /^[0-9.]+$/.test(host);
}

function buildTunSniffing(settings: AppSettings | undefined): XraySniffingConfig | undefined {
  const destOverride = new Array<string>();
  const sniffAllTlsAndHttp = settings === undefined || settings.sniffingEnabled;
  const fakeDns = settings !== undefined && settings.fakeDnsEnabled;
  const routeOnly = settings !== undefined && settings.routeOnlyEnabled;
  if (sniffAllTlsAndHttp) {
    destOverride.push('http');
    destOverride.push('tls');
    destOverride.push('quic');
  }
  if (fakeDns) {
    destOverride.push('fakedns');
  }
  if (destOverride.length === 0 && !routeOnly) {
    return undefined;
  }
  const sniffing: XraySniffingConfig = {
    enabled: fakeDns || sniffAllTlsAndHttp,
    destOverride
  };
  if (routeOnly) {
    sniffing.routeOnly = true;
  }
  return sniffing;
}

function buildFakeDnsDomains(settings: AppSettings): Array<string> {
  const domains: Array<string> = ['geosite:cn'];
  for (let index = 0; index < settings.routingRules.length; index++) {
    const rule = settings.routingRules[index];
    if (!rule.enabled || (rule.outboundTag !== 'direct' && rule.outboundTag !== 'proxy')) {
      continue;
    }
    addStringArrayValues(domains, rule.domain);
  }
  return domains;
}

function ensureOutboundSockopt(outbound: XrayOutbound): Record<string, Object | string | number | boolean | undefined> {
  const streamSettings = (outbound.streamSettings ?? {}) as Record<string, Object | string | number | boolean | undefined>;
  const existing = streamSettings['sockopt'];
  let sockopt: Record<string, Object | string | number | boolean | undefined> = {};
  if (existing !== undefined) {
    sockopt = existing as Record<string, Object | string | number | boolean | undefined>;
  }
  streamSettings['sockopt'] = sockopt;
  outbound.streamSettings = streamSettings;
  return sockopt;
}

function resolveLocalProxyHost(settings: AppSettings): string {
  return settings.proxySharingEnabled ? LOCAL_HTTP_PROXY_LAN_HOST : LOCAL_HTTP_PROXY_HOST;
}

function buildRoutingRules(settings: AppSettings | undefined, proxyBalancerTag?: string): Array<XrayRoutingRule> {
  const rules = new Array<XrayRoutingRule>();
  if (settings === undefined) {
    return rules;
  }

  // Ad-block applies in every traffic mode and must precede the direct/bypass
  // rules so ad/tracker domains are dropped even when they would otherwise be
  // matched by a direct rule (e.g. a CN ad domain under bypass-cn).
  if (settings.adBlockEnabled) {
    const adBlockRule: XrayRoutingRule = {
      type: 'field',
      outboundTag: 'block',
      domain: ['geosite:category-ads-all']
    };
    rules.push(adBlockRule);
  }

  if (settings.trafficMode === 'direct') {
    const directAll: XrayRoutingRule = {
      type: 'field',
      outboundTag: 'direct',
      network: 'tcp,udp'
    };
    rules.push(directAll);
    return rules;
  }

  appendCustomRoutingRules(rules, settings.routingRules, canUseProcessRouting(settings), proxyBalancerTag);

  if (settings.trafficMode === 'rules' && settings.routeOnlyEnabled) {
    const rule: XrayRoutingRule = {
      type: 'field',
      outboundTag: 'direct',
      ip: normalizeRoutingRuleIps([GEOIP_PRIVATE_RULE, GEOIP_CN_EXPECT]),
      domain: ['geosite:cn']
    };
    rules.push(rule);
  }
  return rules;
}

export function canUseProcessRouting(settings: AppSettings | undefined): boolean {
  return settings !== undefined && settings.routeOnlyEnabled && !settings.useHevTun;
}

function appendCustomRoutingRules(rules: Array<XrayRoutingRule>, customRules: Array<RoutingRule>, allowProcessRouting: boolean, proxyBalancerTag?: string): void {
  for (let index = 0; index < customRules.length; index++) {
    const rule = buildCustomRoutingRule(customRules[index], allowProcessRouting, proxyBalancerTag);
    if (rule !== undefined) {
      rules.push(rule);
    }
  }
}

function buildCustomRoutingRule(item: RoutingRule, allowProcessRouting: boolean, proxyBalancerTag?: string): XrayRoutingRule | undefined {
  if (!item.enabled) {
    return undefined;
  }

  const rule: XrayRoutingRule = {
    type: 'field'
  };
  applyRoutingTarget(rule, normalizeRoutingTarget(item.outboundTag, proxyBalancerTag));
  let hasMatcher = false;

  if (item.domain.length > 0) {
    rule.domain = item.domain.slice();
    hasMatcher = true;
  }
  if (item.ip.length > 0) {
    rule.ip = normalizeRoutingRuleIps(item.ip);
    hasMatcher = true;
  }
  if (allowProcessRouting && item.process.length > 0) {
    const processList = normalizeRoutingRuleProcesses(item.process);
    if (processList.length > 0) {
      rule.process = processList;
      hasMatcher = true;
    }
  }
  if (item.port.trim().length > 0) {
    rule.port = item.port.trim();
    hasMatcher = true;
  }
  if (item.protocol.length > 0) {
    rule.protocol = item.protocol.slice();
    hasMatcher = true;
  }
  if (item.network.trim().length > 0) {
    rule.network = item.network.trim();
    hasMatcher = true;
  }

  return hasMatcher ? rule : undefined;
}

function normalizeRoutingRuleIps(ipList: Array<string>): Array<string> {
  const result = new Array<string>();
  for (let index = 0; index < ipList.length; index++) {
    const ip = ipList[index];
    if (ip === GEOIP_CN_EXPECT) {
      result.push(GEOIP_CN_ROUTING_EXT);
    } else if (ip === GEOIP_PRIVATE_RULE) {
      result.push(GEOIP_PRIVATE_ROUTING_EXT);
    } else {
      result.push(ip);
    }
  }
  return result;
}

export function normalizeRoutingRuleProcesses(processList: Array<string>, uidResolver: RoutingProcessUidResolver = resolveProcessUid): Array<string> {
  const result = new Array<string>();
  for (let index = 0; index < processList.length; index++) {
    const packageName = processList[index].trim();
    if (packageName.length === 0) {
      continue;
    }
    if (packageName === UNIDENTIFIED_PROCESS_PACKAGE) {
      result.push(UNIDENTIFIED_PROCESS_UID);
      continue;
    }
    const uid = uidResolver(packageName);
    if (uid !== undefined && isProcessUid(uid)) {
      result.push(uid);
    }
  }
  return result;
}

function resolveProcessUid(packageName: string): string | undefined {
  const cached = PROCESS_UID_CACHE[packageName];
  if (cached !== undefined) {
    return cached;
  }
  try {
    const info = bundleManager.getBundleInfoSync(
      packageName,
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    );
    const uid = info.appInfo.uid.toString();
    PROCESS_UID_CACHE[packageName] = uid;
    return uid;
  } catch (error) {
    return undefined;
  }
}

function isProcessUid(value: string): boolean {
  return /^-?\d+$/.test(value.trim());
}

function normalizeRoutingTarget(value: string, proxyBalancerTag?: string): XrayRoutingTarget {
  const advancedTag = value.trim();
  if (advancedTag === 'policy-group') {
    return buildProxyRoutingTarget(proxyBalancerTag);
  }
  if (advancedTag === 'proxy-chain') {
    return buildProxyRoutingTarget(proxyBalancerTag);
  }

  const outboundTag = normalizeOutboundTag(value);
  if (outboundTag === 'proxy' && proxyBalancerTag !== undefined) {
    return {
      balancerTag: proxyBalancerTag
    };
  }
  return {
    outboundTag
  };
}

function normalizeOutboundTag(value: string): string {
  const tag = value.trim();
  if (tag === 'direct' || tag === 'block' || tag === 'proxy') {
    return tag;
  }
  return 'proxy';
}

function buildProxyRoutingTarget(proxyBalancerTag?: string): XrayRoutingTarget {
  if (proxyBalancerTag !== undefined) {
    return {
      balancerTag: proxyBalancerTag
    };
  }
  return {
    outboundTag: 'proxy'
  };
}

function applyRoutingTarget(rule: XrayRoutingRule, target: XrayRoutingTarget): void {
  if (target.balancerTag !== undefined) {
    rule.balancerTag = target.balancerTag;
    return;
  }
  rule.outboundTag = target.outboundTag ?? 'proxy';
}

function appendDefaultProxyBalancerRule(rules: Array<XrayRoutingRule>, proxyBalancerTag?: string, inboundTags: Array<string> = ['tun-in']): void {
  if (proxyBalancerTag === undefined || inboundTags.length === 0) {
    return;
  }
  rules.push({
    type: 'field',
    inboundTag: inboundTags.slice(),
    network: 'tcp,udp',
    balancerTag: proxyBalancerTag
  });
}

function addCsvValues(target: Array<string | XrayDnsServerConfig>, value: string): void {
  const parts = value.split(',');
  for (let index = 0; index < parts.length; index++) {
    const item = parts[index].trim();
    if (item.length > 0 && target.indexOf(item) < 0) {
      target.push(item);
    }
  }
}

function parseCsvStrings(value: string): Array<string> {
  const result = new Array<string>();
  const parts = value.split(',');
  for (let index = 0; index < parts.length; index++) {
    addUniqueString(result, parts[index]);
  }
  return result;
}

function addUniqueString(target: Array<string>, value: string): void {
  const item = value.trim();
  if (item.length > 0 && target.indexOf(item) < 0) {
    target.push(item);
  }
}

function addStringArrayValues(target: Array<string>, values: Array<string>): void {
  for (let index = 0; index < values.length; index++) {
    addUniqueString(target, values[index]);
  }
}
