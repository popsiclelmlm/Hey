import { AppSettings, DEFAULT_VPN_MTU, GeneratedXrayConfig, normalizeVpnMtuValue, RoutingRule, ValidationResult, XrayConfigType } from './Profile';
import { isSupportedShareLink, isWireguardConfigFile, parseShareLinkToOutboundJson, parseWireguardConfigToOutboundJson } from './ShareLinkParser';

interface XrayOutbound {
  protocol?: string;
  tag?: string;
  settings?: Object;
  streamSettings?: Object;
  mux?: XrayMuxConfig;
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
}

interface XrayFragmentConfig {
  packets: string;
  length: string;
  interval: string;
}

interface XrayHappyEyeballsConfig {
  prioritizeIPv6: boolean;
  interleave: number;
}

interface XrayDnsServerConfig {
  address: string;
  domains?: Array<string>;
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
export const LOCAL_HTTP_PROXY_PORT: number = 10808;
export const LOCAL_SOCKS_PROXY_PORT: number = 10809;
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
const DEFAULT_LOG_LEVEL: string = 'warning';
const DEFAULT_ROUTING_DOMAIN_STRATEGY: string = 'AsIs';

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
      configJson: validation.normalizedJson
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
    applyOutboundRuntimeSettings(outbound, settings);
    outbounds.push(outbound);
  }
  for (let index = 0; index < outbounds.length - 1; index++) {
    const sockopt = ensureOutboundSockopt(outbounds[index]);
    sockopt['dialerProxy'] = outbounds[index + 1].tag;
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
  const url = settings === undefined ? '' : settings.delayTestUrl.trim();
  return url.length > 0 ? url : 'https://www.gstatic.com/generate_204';
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
  if (settings !== undefined && settings.muxEnabled) {
    const mux: XrayMuxConfig = {
      enabled: true,
      concurrency: settings.muxConcurrency,
      xudpConcurrency: settings.muxXudpConcurrency,
      xudpProxyUDP443: settings.muxXudpQuic
    };
    outbound.mux = mux;
  }
  if (settings !== undefined && settings.fragmentEnabled) {
    const sockopt = ensureOutboundSockopt(outbound);
    const fragment: XrayFragmentConfig = {
      packets: settings.fragmentPackets,
      length: settings.fragmentLength,
      interval: settings.fragmentInterval
    };
    sockopt['fragment'] = fragment;
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

  const metricsInbound: XrayInboundConfig = {
    tag: METRICS_IN_TAG,
    listen: METRICS_HOST,
    port: METRICS_PORT,
    protocol: 'dokodemo-door',
    settings: new DokodemoInboundSettings()
  };

  const inbounds: Array<XrayInboundConfig> = [tunInbound, metricsInbound];
  const outbounds: Array<XrayOutbound> = proxyOutbounds.concat([directOutbound, blockOutbound]);

  // Route the metrics inbound to the metrics handler ahead of any user/traffic
  // rule so the local /debug/vars probe is never proxied or blocked.
  const proxyTarget = buildProxyRoutingTarget(balancer?.tag);
  const routingRules = buildRoutingRules(settings, balancer?.tag);
  const metricsRule: XrayRoutingRule = {
    type: 'field',
    inboundTag: [METRICS_IN_TAG],
    outboundTag: METRICS_OUT_TAG
  };

  if (settings !== undefined && settings.appendHttpProxy) {
    const httpInboundTag = 'http-in';
    const httpProxyHost = resolveLocalProxyHost(settings);
    const httpInbound: XrayInboundConfig = {
      tag: httpInboundTag,
      listen: httpProxyHost,
      port: LOCAL_HTTP_PROXY_PORT,
      protocol: 'http',
      settings: new HttpInboundSettings()
    };
    const httpProxyRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: [httpInboundTag]
    };
    applyRoutingTarget(httpProxyRule, proxyTarget);
    inbounds.push(httpInbound);
    routingRules.unshift(httpProxyRule);
  }
  if (settings !== undefined && settings.localSocksEnabled) {
    const socksInboundTag = 'socks-in';
    const socksInbound: XrayInboundConfig = {
      tag: socksInboundTag,
      listen: resolveLocalProxyHost(settings),
      port: settings.localSocksPort,
      protocol: 'socks',
      settings: new SocksInboundSettings(
        settings.localSocksUdpEnabled,
        settings.localSocksUsername,
        settings.localSocksPassword
      )
    };
    const socksProxyRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: [socksInboundTag]
    };
    applyRoutingTarget(socksProxyRule, proxyTarget);
    inbounds.push(socksInbound);
    routingRules.unshift(socksProxyRule);
  }
  if (settings !== undefined && settings.localDnsEnabled) {
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
  routingRules.unshift(metricsRule);

  const policy: XrayPolicyConfig = {
    system: {
      statsInboundUplink: true,
      statsInboundDownlink: true,
      statsOutboundUplink: true,
      statsOutboundDownlink: true
    }
  };

  const config: XrayFullConfig = {
    log: {
      loglevel: settings?.logLevel ?? DEFAULT_LOG_LEVEL
    },
    dns: buildDnsConfig(settings),
    inbounds,
    outbounds,
    routing: {
      domainStrategy: settings?.routingDomainStrategy ?? DEFAULT_ROUTING_DOMAIN_STRATEGY,
      rules: routingRules
    },
    stats: new EmptySettings(),
    metrics: {
      tag: METRICS_OUT_TAG
    },
    policy
  };
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

  const runtimeHttpProxyHost = settings !== undefined && settings.appendHttpProxy ? resolveLocalProxyHost(settings) : undefined;
  const runtimeHttpProxyPort = settings !== undefined && settings.appendHttpProxy ? LOCAL_HTTP_PROXY_PORT : undefined;
  const runtimeSocksHost = settings !== undefined && settings.localSocksEnabled ? resolveLocalProxyHost(settings) : undefined;
  const runtimeSocksPort = settings !== undefined && settings.localSocksEnabled ? settings.localSocksPort : undefined;

  return {
    configJson: JSON.stringify(config, null, 2),
    socksHost: runtimeSocksHost,
    socksPort: runtimeSocksPort,
    httpProxyHost: runtimeHttpProxyHost,
    httpProxyPort: runtimeHttpProxyPort,
    metricsServer: METRICS_SERVER_URL
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
  const servers: Array<string | XrayDnsServerConfig> = [];
  addCsvValues(servers, settings.remoteDns);
  addCsvValues(servers, settings.domesticDns);
  if (servers.length === 0) {
    servers.push('1.1.1.1');
  }
  const dns: XrayDnsConfig = {
    servers
  };
  if (settings.localDnsEnabled && settings.fakeDnsEnabled) {
    dns.servers.unshift({
      address: 'fakedns',
      domains: buildFakeDnsDomains(settings)
    });
  }
  if (settings.dnsHosts.length > 0) {
    try {
      dns.hosts = JSON.parse(settings.dnsHosts) as Object;
    } catch (error) {
      dns.hosts = new EmptySettings();
    }
  }
  return dns;
}

function buildTunSniffing(settings: AppSettings | undefined): XraySniffingConfig | undefined {
  const destOverride = new Array<string>();
  if (settings === undefined || settings.sniffingEnabled) {
    destOverride.push('http');
    destOverride.push('tls');
    destOverride.push('quic');
  }
  if (settings !== undefined && settings.localDnsEnabled && settings.fakeDnsEnabled) {
    destOverride.push('fakedns');
  }
  if (destOverride.length === 0) {
    return undefined;
  }
  return {
    enabled: true,
    destOverride
  };
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
    appendDefaultProxyBalancerRule(rules, proxyBalancerTag);
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

  appendCustomRoutingRules(rules, settings.routingRules, proxyBalancerTag);

  if (settings.trafficMode === 'rules' && settings.routeOnlyEnabled) {
    const rule: XrayRoutingRule = {
      type: 'field',
      outboundTag: 'direct',
      ip: ['geoip:private', 'geoip:cn'],
      domain: ['geosite:cn']
    };
    rules.push(rule);
  }
  appendDefaultProxyBalancerRule(rules, proxyBalancerTag);
  return rules;
}

function appendCustomRoutingRules(rules: Array<XrayRoutingRule>, customRules: Array<RoutingRule>, proxyBalancerTag?: string): void {
  for (let index = 0; index < customRules.length; index++) {
    const rule = buildCustomRoutingRule(customRules[index], proxyBalancerTag);
    if (rule !== undefined) {
      rules.push(rule);
    }
  }
}

function buildCustomRoutingRule(item: RoutingRule, proxyBalancerTag?: string): XrayRoutingRule | undefined {
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
    rule.ip = item.ip.slice();
    hasMatcher = true;
  }
  if (item.process.length > 0) {
    rule.process = item.process.slice();
    hasMatcher = true;
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

function normalizeRoutingTarget(value: string, proxyBalancerTag?: string): XrayRoutingTarget {
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

function appendDefaultProxyBalancerRule(rules: Array<XrayRoutingRule>, proxyBalancerTag?: string): void {
  if (proxyBalancerTag === undefined) {
    return;
  }
  rules.push({
    type: 'field',
    inboundTag: ['tun-in'],
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

function addStringArrayValues(target: Array<string>, values: Array<string>): void {
  for (let index = 0; index < values.length; index++) {
    const item = values[index].trim();
    if (item.length > 0 && target.indexOf(item) < 0) {
      target.push(item);
    }
  }
}
