import { normalizeV2rayNgStreamAlpnWithFallback } from './V2rayNgOptions';

export interface ManualOutboundBuildResult {
  success: boolean;
  message: string;
  protocol: string;
  outboundJson: string;
}

export interface ManualWireguardInput {
  tag: string;
  host: string;
  port: string;
  secretKey: string;
  publicKey: string;
  preSharedKey: string;
  localAddress: string;
  reserved: string;
  mtu: string;
}

export interface ManualHysteria2Input {
  tag: string;
  host: string;
  port: string;
  password: string;
  sni: string;
  alpn: string;
  allowInsecure: boolean;
  obfsPassword: string;
  portHopping: string;
  portHoppingInterval: string;
  pinSHA256: string;
  bandwidthDown: string;
  bandwidthUp: string;
}

interface ManualWireguardPeer {
  publicKey: string;
  endpoint: string;
  preSharedKey?: string;
}

interface ManualWireguardSettings {
  secretKey: string;
  address: Array<string>;
  peers: Array<ManualWireguardPeer>;
  mtu?: number;
  reserved?: Array<number>;
}

interface ManualHysteria2Server {
  address: string;
  port: number;
  password: string;
  sni?: string;
  alpn?: string;
  insecure?: boolean;
  obfsPassword?: string;
  portHopping?: string;
  portHoppingInterval?: string;
  pinSHA256?: string;
  bandwidthDown?: string;
  bandwidthUp?: string;
}

interface ManualHysteria2Settings {
  servers: Array<ManualHysteria2Server>;
}

interface ManualOutbound {
  protocol: string;
  tag: string;
  settings: ManualWireguardSettings | ManualHysteria2Settings;
}

const DEFAULT_WIREGUARD_RESERVED: Array<number> = [0, 0, 0];

export function buildManualWireguardOutbound(input: ManualWireguardInput): ManualOutboundBuildResult {
  const host = input.host.trim();
  const port = parsePort(input.port);
  if (host.length === 0 || port === 0) {
    return makeFailure('请填写有效的服务器和端口。', 'wireguard');
  }

  const secretKey = input.secretKey.trim();
  if (secretKey.length === 0) {
    return makeFailure('WireGuard 链接缺少私钥。', 'wireguard');
  }

  const publicKey = input.publicKey.trim();
  if (publicKey.length === 0) {
    return makeFailure('WireGuard 链接缺少 publickey。', 'wireguard');
  }

  const peer: ManualWireguardPeer = {
    publicKey,
    endpoint: formatEndpoint(host, port)
  };
  const preSharedKey = input.preSharedKey.trim();
  if (preSharedKey.length > 0) {
    peer.preSharedKey = preSharedKey;
  }

  const settings: ManualWireguardSettings = {
    secretKey,
    address: splitCsvWithDefault(input.localAddress, '172.16.0.2/32'),
    peers: [peer],
    mtu: parsePositiveInt(input.mtu, 1420)
  };
  settings.reserved = parseNumberCsvWithDefault(input.reserved, DEFAULT_WIREGUARD_RESERVED);

  return makeSuccess('wireguard', {
    protocol: 'wireguard',
    tag: normalizeTag(input.tag),
    settings
  });
}

export function buildManualHysteria2Outbound(input: ManualHysteria2Input): ManualOutboundBuildResult {
  const host = input.host.trim();
  const port = parsePort(input.port);
  if (host.length === 0 || port === 0) {
    return makeFailure('请填写有效的服务器和端口。', 'hysteria2');
  }

  const password = input.password.trim();
  if (password.length === 0) {
    return makeFailure('Hysteria2 链接缺少认证密码。', 'hysteria2');
  }

  const server: ManualHysteria2Server = {
    address: host,
    port,
    password,
    insecure: input.allowInsecure
  };
  assignIfPresent(server, 'sni', input.sni);
  assignIfPresent(server, 'alpn', normalizeV2rayNgStreamAlpnWithFallback(input.alpn, 'h3'));
  assignIfPresent(server, 'obfsPassword', input.obfsPassword);
  assignIfPresent(server, 'portHopping', input.portHopping);
  assignIfPresent(server, 'portHoppingInterval', input.portHoppingInterval);
  assignIfPresent(server, 'pinSHA256', input.pinSHA256);
  assignIfPresent(server, 'bandwidthDown', input.bandwidthDown);
  assignIfPresent(server, 'bandwidthUp', input.bandwidthUp);

  return makeSuccess('hysteria2', {
    protocol: 'hysteria2',
    tag: normalizeTag(input.tag),
    settings: {
      servers: [server]
    }
  });
}

function makeSuccess(protocol: string, outbound: ManualOutbound): ManualOutboundBuildResult {
  return {
    success: true,
    message: `${protocol.toUpperCase()} outbound 生成成功。`,
    protocol,
    outboundJson: JSON.stringify(outbound, null, 2)
  };
}

function makeFailure(message: string, protocol: string): ManualOutboundBuildResult {
  return {
    success: false,
    message,
    protocol,
    outboundJson: ''
  };
}

function parsePort(value: string): number {
  const port = Number(value.trim());
  if (Number.isNaN(port) || port < 1 || port > 65535) {
    return 0;
  }
  return Math.floor(port);
}

function parsePositiveInt(value: string, fallback: number): number {
  const parsed = Number(value.trim());
  if (Number.isNaN(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.floor(parsed);
}

function splitCsvWithDefault(value: string, fallback: string): Array<string> {
  const result = value.split(',').map(item => item.trim()).filter(item => item.length > 0);
  if (result.length === 0) {
    result.push(fallback);
  }
  return result;
}

function parseNumberCsv(value: string): Array<number> {
  const result = new Array<number>();
  const parts = value.split(',');
  for (let index = 0; index < parts.length; index++) {
    const item = parts[index].trim();
    if (item.length === 0) {
      continue;
    }
    const parsed = Number(item);
    if (!Number.isNaN(parsed)) {
      result.push(Math.floor(parsed));
    }
  }
  return result;
}

function parseNumberCsvWithDefault(value: string, fallback: Array<number>): Array<number> {
  const result = parseNumberCsv(value);
  if (result.length > 0) {
    return result;
  }
  return fallback.slice();
}

function formatEndpoint(host: string, port: number): string {
  if (host.indexOf(':') >= 0 && !host.startsWith('[')) {
    return `[${host}]:${port}`;
  }
  return `${host}:${port}`;
}

function normalizeTag(value: string): string {
  const tag = value.trim();
  return tag.length > 0 ? tag : 'proxy';
}

function assignIfPresent(server: ManualHysteria2Server, key: string, value: string): void {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return;
  }
  if (key === 'sni') {
    server.sni = trimmed;
  } else if (key === 'alpn') {
    server.alpn = trimmed;
  } else if (key === 'obfsPassword') {
    server.obfsPassword = trimmed;
  } else if (key === 'portHopping') {
    server.portHopping = trimmed;
  } else if (key === 'portHoppingInterval') {
    server.portHoppingInterval = trimmed;
  } else if (key === 'pinSHA256') {
    server.pinSHA256 = trimmed;
  } else if (key === 'bandwidthDown') {
    server.bandwidthDown = trimmed;
  } else if (key === 'bandwidthUp') {
    server.bandwidthUp = trimmed;
  }
}
