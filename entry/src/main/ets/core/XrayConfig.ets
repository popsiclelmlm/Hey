import { AppSettings, GeneratedXrayConfig, RoutingRule, ValidationResult } from './Profile';
import { isSupportedShareLink, parseShareLinkToOutboundJson } from './ShareLinkParser';

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

interface XrayInboundConfig {
  tag: string;
  listen?: string;
  port?: number;
  protocol: string;
  settings: Object;
  sniffing?: XraySniffingConfig;
}

interface XrayDnsConfig {
  servers: Array<string>;
  hosts?: Object;
}

interface XrayRoutingRule {
  type: string;
  outboundTag: string;
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

interface XrayFullConfig {
  log: XrayLogConfig;
  dns?: XrayDnsConfig;
  inbounds: Array<XrayInboundConfig>;
  outbounds: Array<XrayOutbound>;
  routing: XrayRoutingConfig;
  stats?: Object;
  metrics?: XrayMetricsConfig;
  policy?: XrayPolicyConfig;
}

class SocksInboundSettings {
  auth: string = 'noauth';
  udp: boolean = true;
  userLevel: number = 0;
}

class HttpInboundSettings {
  auth: string = 'noauth';
  userLevel: number = 0;
}

class TunInboundSettings {
  name: string = 'vpn-tun';
  mtu: number = 1400;
  userLevel: number = 0;
}

class DokodemoInboundSettings {
  address: string = '127.0.0.1';
}

class EmptySettings {
}

const SUPPORTED_PROTOCOLS: Array<string> = ['vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http', 'wireguard', 'hysteria2'];

export const DEFAULT_SOCKS_HOST: string = '127.0.0.1';
export const LOCAL_HTTP_PROXY_HOST: string = '127.0.0.1';
export const LOCAL_HTTP_PROXY_PORT: number = 10808;
export const DELAY_TEST_SOCKS_PORT: number = 10825;
// Local Xray metrics (expvar) endpoint. The generated VPN config exposes a
// dokodemo inbound on this port routed to the metrics handler so that
// CGoQueryStats can read real per-tag traffic counters from /debug/vars.
export const METRICS_HOST: string = '127.0.0.1';
export const METRICS_PORT: number = 10845;
export const METRICS_SERVER_URL: string = 'http://127.0.0.1:10845/debug/vars';
const METRICS_OUT_TAG: string = 'metrics_out';
const METRICS_IN_TAG: string = 'metrics_in';
const DEFAULT_LOG_LEVEL: string = 'warning';
const DEFAULT_ROUTING_DOMAIN_STRATEGY: string = 'AsIs';

function isSupportedProtocol(protocol: string): boolean {
  return SUPPORTED_PROTOCOLS.indexOf(protocol.toLowerCase()) >= 0;
}

function parseOutbound(outboundJson: string): XrayOutbound {
  return JSON.parse(outboundJson) as XrayOutbound;
}

export function validateOutboundJson(outboundJson: string): ValidationResult {
  const trimmed = outboundJson.trim();
  if (trimmed.length === 0) {
    return {
      valid: false,
      message: '请先粘贴 Xray outbound JSON。',
      protocol: '',
      normalizedJson: ''
    };
  }

  try {
    const outbound = parseOutbound(trimmed);
    if (outbound.protocol === undefined || outbound.protocol.trim().length === 0) {
      return {
        valid: false,
        message: 'outbound 缺少 protocol 字段。',
        protocol: '',
        normalizedJson: ''
      };
    }

    if (!isSupportedProtocol(outbound.protocol)) {
      return {
        valid: false,
        message: `暂不支持 ${outbound.protocol}，当前支持 VLESS、VMess、Trojan、Shadowsocks、SOCKS、HTTP、WireGuard 和 Hysteria2。`,
        protocol: outbound.protocol,
        normalizedJson: ''
      };
    }

    if (outbound.settings === undefined) {
      return {
        valid: false,
        message: 'outbound 缺少 settings 字段。',
        protocol: outbound.protocol,
        normalizedJson: ''
      };
    }

    return {
      valid: true,
      message: `${outbound.protocol.toUpperCase()} outbound 校验通过。`,
      protocol: outbound.protocol,
      normalizedJson: JSON.stringify(outbound, null, 2)
    };
  } catch (error) {
    return {
      valid: false,
      message: `JSON 解析失败：${JSON.stringify(error)}`,
      protocol: '',
      normalizedJson: ''
    };
  }
}

export function normalizeOutboundInput(input: string): ValidationResult {
  const trimmed = input.trim();
  if (!isSupportedShareLink(trimmed)) {
    return validateOutboundJson(trimmed);
  }

  const imported = parseShareLinkToOutboundJson(trimmed);
  if (!imported.success) {
    return {
      valid: false,
      message: imported.message,
      protocol: imported.protocol,
      normalizedJson: ''
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
    normalizedJson: validation.normalizedJson
  };
}

export function buildXrayConfig(outboundJson: string): GeneratedXrayConfig {
  return buildXrayConfigInternal(outboundJson, undefined);
}

export function buildXrayConfigWithSettings(outboundJson: string, settings: AppSettings): GeneratedXrayConfig {
  return buildXrayConfigInternal(outboundJson, settings);
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
    const streamSettings = (outbound.streamSettings ?? {}) as Record<string, Object | undefined>;
    const sockopt = (streamSettings['sockopt'] ?? {}) as Record<string, Object | undefined>;
    const fragment: XrayFragmentConfig = {
      packets: settings.fragmentPackets,
      length: settings.fragmentLength,
      interval: settings.fragmentInterval
    };
    sockopt['fragment'] = fragment;
    streamSettings['sockopt'] = sockopt;
    outbound.streamSettings = streamSettings;
  }

  const tunInbound: XrayInboundConfig = {
    tag: 'tun-in',
    protocol: 'tun',
    settings: new TunInboundSettings()
  };
  if (settings === undefined || settings.sniffingEnabled) {
    const sniffing: XraySniffingConfig = {
      enabled: true,
      destOverride: ['http', 'tls', 'quic']
    };
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

  // Route the metrics inbound to the metrics handler ahead of any user/traffic
  // rule so the local /debug/vars probe is never proxied or blocked.
  const routingRules = buildRoutingRules(settings);
  const metricsRule: XrayRoutingRule = {
    type: 'field',
    inboundTag: [METRICS_IN_TAG],
    outboundTag: METRICS_OUT_TAG
  };

  if (settings !== undefined && settings.appendHttpProxy) {
    const httpInboundTag = 'http-in';
    const httpInbound: XrayInboundConfig = {
      tag: httpInboundTag,
      listen: LOCAL_HTTP_PROXY_HOST,
      port: LOCAL_HTTP_PROXY_PORT,
      protocol: 'http',
      settings: new HttpInboundSettings()
    };
    const httpProxyRule: XrayRoutingRule = {
      type: 'field',
      inboundTag: [httpInboundTag],
      outboundTag: 'proxy'
    };
    inbounds.push(httpInbound);
    routingRules.unshift(httpProxyRule);
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
    outbounds: [outbound, directOutbound, blockOutbound],
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

  return {
    configJson: JSON.stringify(config, null, 2),
    httpProxyHost: settings?.appendHttpProxy ? LOCAL_HTTP_PROXY_HOST : undefined,
    httpProxyPort: settings?.appendHttpProxy ? LOCAL_HTTP_PROXY_PORT : undefined,
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
  const servers: Array<string> = [];
  addCsvValues(servers, settings.remoteDns);
  addCsvValues(servers, settings.domesticDns);
  if (servers.length === 0) {
    servers.push('1.1.1.1');
  }
  const dns: XrayDnsConfig = {
    servers
  };
  if (settings.dnsHosts.length > 0) {
    try {
      dns.hosts = JSON.parse(settings.dnsHosts) as Object;
    } catch (error) {
      dns.hosts = new EmptySettings();
    }
  }
  return dns;
}

function buildRoutingRules(settings: AppSettings | undefined): Array<XrayRoutingRule> {
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

  appendCustomRoutingRules(rules, settings.routingRules);

  if (settings.trafficMode === 'rules' && settings.routeOnlyEnabled) {
    const rule: XrayRoutingRule = {
      type: 'field',
      outboundTag: 'direct',
      ip: ['geoip:private', 'geoip:cn'],
      domain: ['geosite:cn']
    };
    rules.push(rule);
  }
  return rules;
}

function appendCustomRoutingRules(rules: Array<XrayRoutingRule>, customRules: Array<RoutingRule>): void {
  for (let index = 0; index < customRules.length; index++) {
    const rule = buildCustomRoutingRule(customRules[index]);
    if (rule !== undefined) {
      rules.push(rule);
    }
  }
}

function buildCustomRoutingRule(item: RoutingRule): XrayRoutingRule | undefined {
  if (!item.enabled) {
    return undefined;
  }

  const rule: XrayRoutingRule = {
    type: 'field',
    outboundTag: normalizeOutboundTag(item.outboundTag)
  };
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

function normalizeOutboundTag(value: string): string {
  const tag = value.trim();
  if (tag === 'direct' || tag === 'block' || tag === 'proxy') {
    return tag;
  }
  return 'proxy';
}

function addCsvValues(target: Array<string>, value: string): void {
  const parts = value.split(',');
  for (let index = 0; index < parts.length; index++) {
    const item = parts[index].trim();
    if (item.length > 0) {
      target.push(item);
    }
  }
}
