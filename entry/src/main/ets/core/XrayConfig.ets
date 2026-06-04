import { AppSettings, GeneratedXrayConfig, ValidationResult } from './Profile';
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
  ip?: Array<string>;
  domain?: Array<string>;
  network?: string;
}

interface XrayRoutingConfig {
  domainStrategy: string;
  rules: Array<XrayRoutingRule>;
}

interface XrayFullConfig {
  log: XrayLogConfig;
  dns?: XrayDnsConfig;
  inbounds: Array<XrayInboundConfig>;
  outbounds: Array<XrayOutbound>;
  routing: XrayRoutingConfig;
}

class SocksInboundSettings {
  auth: string = 'noauth';
  udp: boolean = true;
  userLevel: number = 0;
}

class TunInboundSettings {
  name: string = 'vpn-tun';
  mtu: number = 1400;
  userLevel: number = 0;
}

class EmptySettings {
}

const SUPPORTED_PROTOCOLS: Array<string> = ['vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http', 'wireguard', 'hysteria2'];

export const DEFAULT_SOCKS_HOST: string = '127.0.0.1';
export const DELAY_TEST_SOCKS_PORT: number = 10825;
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
    sockopt['fragment'] = {
      packets: settings.fragmentPackets,
      length: settings.fragmentLength,
      interval: settings.fragmentInterval
    };
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

  const config: XrayFullConfig = {
    log: {
      loglevel: settings?.logLevel ?? DEFAULT_LOG_LEVEL
    },
    dns: buildDnsConfig(settings),
    inbounds: [tunInbound],
    outbounds: [outbound, directOutbound, blockOutbound],
    routing: {
      domainStrategy: settings?.routingDomainStrategy ?? DEFAULT_ROUTING_DOMAIN_STRATEGY,
      rules: buildRoutingRules(settings)
    }
  };

  return {
    configJson: JSON.stringify(config, null, 2)
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

  if (settings.trafficMode === 'direct') {
    const directAll: XrayRoutingRule = {
      type: 'field',
      outboundTag: 'direct',
      network: 'tcp,udp'
    };
    rules.push(directAll);
    return rules;
  }

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

function addCsvValues(target: Array<string>, value: string): void {
  const parts = value.split(',');
  for (let index = 0; index < parts.length; index++) {
    const item = parts[index].trim();
    if (item.length > 0) {
      target.push(item);
    }
  }
}
