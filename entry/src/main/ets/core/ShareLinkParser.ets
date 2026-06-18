import { decodeBase64ToUtf8, encodeUtf8ToBase64 } from './Encoding';
import { buildKcpFinalMask, isCanonicalKcpFinalMask, readKcpShareParamsFromFinalMask } from './KcpTransport';

export interface ShareLinkParseResult {
  success: boolean;
  message: string;
  protocol: string;
  name: string;
  outboundJson: string;
}

interface HostPort {
  host: string;
  port: number;
}

interface WireguardConfigDocument {
  interfaceParams: Map<string, string>;
  peerParams: Map<string, string>;
}

interface ParsedShareUrl {
  userInfo: string;
  host: string;
  port: number;
  query: Map<string, string>;
  fragment: string;
}

interface XrayTlsSettings {
  allowInsecure?: boolean;
  serverName?: string;
  alpn?: Array<string>;
  fingerprint?: string;
  echConfigList?: string;
  pinnedPeerCertSha256?: string;
  publicKey?: string;
  shortId?: string;
  spiderX?: string;
  mldsa65Verify?: string;
  show?: boolean;
}

interface XrayTcpRequestHeaders {
  Host: Array<string>;
}

interface XrayTcpRequest {
  path: Array<string>;
  headers: XrayTcpRequestHeaders;
}

interface XrayTcpHeader {
  type: string;
  request?: XrayTcpRequest;
}

interface XrayTcpSettings {
  header: XrayTcpHeader;
}

interface XrayWsHeaders {
  Host: string;
}

interface XrayWsSettings {
  path: string;
  headers: XrayWsHeaders;
}

interface XrayHttpUpgradeSettings {
  path: string;
  host: string;
}

interface XrayKcpSettings {
  mtu?: number;
  tti?: number;
}

interface XrayXhttpSettings {
  path: string;
  host: string;
  mode?: string;
  extra?: Object;
}

interface XrayHttpSettings {
  host: Array<string>;
  path: string;
}

interface XrayGrpcSettings {
  serviceName: string;
  authority?: string;
  multiMode?: boolean;
  idle_timeout?: number;
  health_check_timeout?: number;
}

interface XrayStreamSettings {
  network: string;
  security?: string;
  tcpSettings?: XrayTcpSettings;
  kcpSettings?: XrayKcpSettings;
  wsSettings?: XrayWsSettings;
  httpupgradeSettings?: XrayHttpUpgradeSettings;
  xhttpSettings?: XrayXhttpSettings;
  httpSettings?: XrayHttpSettings;
  grpcSettings?: XrayGrpcSettings;
  tlsSettings?: XrayTlsSettings;
  realitySettings?: XrayTlsSettings;
  finalmask?: Object;
}

interface XrayVlessUser {
  id: string;
  encryption: string;
  flow?: string;
}

interface XrayVlessServer {
  address: string;
  port: number;
  users: Array<XrayVlessUser>;
}

interface XrayVlessSettings {
  vnext: Array<XrayVlessServer>;
}

interface XrayVmessUser {
  id: string;
  alterId: number;
  security: string;
}

interface XrayVmessServer {
  address: string;
  port: number;
  users: Array<XrayVmessUser>;
}

interface XrayVmessSettings {
  vnext: Array<XrayVmessServer>;
}

interface XrayTrojanServer {
  address: string;
  port: number;
  password: string;
  flow?: string;
}

interface XrayTrojanSettings {
  servers: Array<XrayTrojanServer>;
}

interface XrayShadowsocksServer {
  address: string;
  port: number;
  method: string;
  password: string;
}

interface XrayShadowsocksSettings {
  servers: Array<XrayShadowsocksServer>;
}

interface XrayGenericUser {
  user: string;
  pass: string;
}

interface XrayGenericServer {
  address: string;
  port: number;
  users?: Array<XrayGenericUser>;
}

interface XrayServerSettings {
  servers: Array<XrayGenericServer>;
}

interface XrayWireguardPeer {
  publicKey: string;
  endpoint: string;
  preSharedKey?: string;
}

interface XrayWireguardSettings {
  secretKey: string;
  address: Array<string>;
  peers: Array<XrayWireguardPeer>;
  mtu?: number;
  reserved?: Array<number>;
}

interface XrayHysteria2Server {
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
}

interface XrayHysteria2Settings {
  servers: Array<XrayHysteria2Server>;
}

interface XrayOutbound {
  protocol: string;
  tag: string;
  settings: XrayVlessSettings | XrayVmessSettings | XrayTrojanSettings | XrayShadowsocksSettings | XrayServerSettings | XrayWireguardSettings | XrayHysteria2Settings;
  streamSettings?: XrayStreamSettings;
}

interface VmessQrCode {
  v?: string;
  ps?: string;
  add?: string;
  port?: string;
  id?: string;
  scy?: string;
  net?: string;
  type?: string;
  host?: string;
  path?: string;
  tls?: string;
  sni?: string;
  fp?: string;
  alpn?: string;
  insecure?: string;
}

function makeFailure(message: string, protocol: string = ''): ShareLinkParseResult {
  return {
    success: false,
    message,
    protocol,
    name: '',
    outboundJson: ''
  };
}

function makeSuccess(protocol: string, name: string, outbound: XrayOutbound): ShareLinkParseResult {
  return {
    success: true,
    message: `${protocol.toUpperCase()} 分享链接导入成功。`,
    protocol,
    name,
    outboundJson: JSON.stringify(outbound, null, 2)
  };
}

function defaultShareName(name: string): string {
  return name.length > 0 ? name : 'none';
}

export const SUPPORTED_SHARE_LINK_SCHEMES: Array<string> = [
  'vless://',
  'vmess://',
  'trojan://',
  'ss://',
  'socks://',
  'socks4://',
  'socks5://',
  'http://',
  'https://',
  'wireguard://',
  'hysteria2://',
  'hy2://'
];

export function buildUnsupportedShareLinkMessage(): string {
  return `暂只支持 ${SUPPORTED_SHARE_LINK_SCHEMES.join('、')} 分享链接。`;
}

export function isSupportedShareLink(input: string): boolean {
  const lower = input.trim().toLowerCase();
  for (let index = 0; index < SUPPORTED_SHARE_LINK_SCHEMES.length; index++) {
    if (lower.startsWith(SUPPORTED_SHARE_LINK_SCHEMES[index])) {
      return true;
    }
  }
  return false;
}

export function isWireguardConfigFile(input: string): boolean {
  const lower = input.trim().toLowerCase();
  return lower.indexOf('[interface]') >= 0 && lower.indexOf('[peer]') >= 0;
}

export function parseShareLinkToOutboundJson(input: string): ShareLinkParseResult {
  const trimmed = input.trim();
  const lower = trimmed.toLowerCase();

  try {
    if (lower.startsWith('vless://')) {
      return parseVlessLink(trimmed);
    }
    if (lower.startsWith('vmess://')) {
      return parseVmessLink(trimmed);
    }
    if (lower.startsWith('trojan://')) {
      return parseTrojanLink(trimmed);
    }
    if (lower.startsWith('ss://')) {
      return parseShadowsocksLink(trimmed);
    }
    if (lower.startsWith('socks://')) {
      return parseSocksLink(trimmed, 'socks');
    }
    if (lower.startsWith('socks4://')) {
      return parseSocksLink(trimmed, 'socks4');
    }
    if (lower.startsWith('socks5://')) {
      return parseSocksLink(trimmed, 'socks5');
    }
    if (lower.startsWith('http://')) {
      return parseHttpProxyLink(trimmed, 'http');
    }
    if (lower.startsWith('https://')) {
      return parseHttpProxyLink(trimmed, 'https');
    }
    if (lower.startsWith('wireguard://')) {
      return parseWireguardLink(trimmed);
    }
    if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
      return parseHysteria2Link(trimmed);
    }
    return makeFailure(buildUnsupportedShareLinkMessage());
  } catch (error) {
    return makeFailure(`分享链接解析失败：${stringifyError(error)}`);
  }
}

export function parseWireguardConfigToOutboundJson(input: string): ShareLinkParseResult {
  try {
    const document = parseWireguardConfigDocument(input);
    const privateKey = mapValue(document.interfaceParams, 'privatekey');
    if (privateKey.length === 0) {
      return makeFailure('WireGuard 链接缺少私钥。', 'wireguard');
    }

    const publicKey = mapValue(document.peerParams, 'publickey');
    if (publicKey.length === 0) {
      return makeFailure('WireGuard 链接缺少 publickey。', 'wireguard');
    }

    const endpoint = mapValue(document.peerParams, 'endpoint');
    if (endpoint.length === 0) {
      return makeFailure('WireGuard 配置缺少 endpoint。', 'wireguard');
    }
    const hostPort = parseHostPort(endpoint);
    const peer: XrayWireguardPeer = {
      publicKey,
      endpoint: formatEndpoint(hostPort.host, hostPort.port)
    };
    const preSharedKey = mapValue(document.peerParams, 'presharedkey');
    if (preSharedKey.length > 0) {
      peer.preSharedKey = preSharedKey;
    }

    const settings: XrayWireguardSettings = {
      secretKey: privateKey,
      address: splitCsvWithDefault(mapValue(document.interfaceParams, 'address'), '172.16.0.2/32'),
      peers: [peer]
    };
    const mtu = parseOptionalPositiveInt(mapValue(document.interfaceParams, 'mtu'));
    if (mtu > 0) {
      settings.mtu = mtu;
    }
    const reserved = parseNumberCsv(mapValue(document.peerParams, 'reserved'));
    if (reserved.length > 0) {
      settings.reserved = reserved;
    }

    const outbound: XrayOutbound = {
      protocol: 'wireguard',
      tag: 'proxy',
      settings
    };
    return {
      success: true,
      message: 'WireGuard 配置文件导入成功。',
      protocol: 'wireguard',
      name: 'WireGuard',
      outboundJson: JSON.stringify(outbound, null, 2)
    };
  } catch (error) {
    return makeFailure(`分享链接解析失败：${stringifyError(error as Error)}`, 'wireguard');
  }
}

function parseVlessLink(input: string): ShareLinkParseResult {
  const parsed = parseUrlStyleShareLink(input, 'vless');
  if (parsed.userInfo.length === 0) {
    return makeFailure('VLESS 链接缺少用户 ID。', 'vless');
  }

  const user: XrayVlessUser = {
    id: parsed.userInfo,
    encryption: queryValue(parsed.query, 'encryption', 'none')
  };
  const flow = queryValue(parsed.query, 'flow', '');
  if (flow.length > 0) {
    user.flow = flow;
  }

  const settings: XrayVlessSettings = {
    vnext: [{
      address: parsed.host,
      port: parsed.port,
      users: [user]
    }]
  };

  const outbound: XrayOutbound = {
    protocol: 'vless',
    tag: 'proxy',
    settings,
    streamSettings: buildStreamSettings(parsed.query, '')
  };
  return makeSuccess('vless', defaultShareName(parsed.fragment), outbound);
}

function parseVmessLink(input: string): ShareLinkParseResult {
  const body = input.substring('vmess://'.length);
  if (body.indexOf('?') > 0 && body.indexOf('&') > 0) {
    return parseVmessAeadLink(input);
  }

  const decoded = decodeBase64ToUtf8(body);
  const vmess = JSON.parse(decoded) as VmessQrCode;
  if (empty(vmess.add) || empty(vmess.port) || empty(vmess.id)) {
    return makeFailure('VMess 链接缺少服务器、端口或用户 ID。', 'vmess');
  }

  const query = new Map<string, string>();
  query.set('type', valueOr(vmess.net, 'tcp'));
  query.set('headerType', valueOr(vmess.type, 'none'));
  query.set('host', valueOr(vmess.host, ''));
  query.set('path', valueOr(vmess.path, ''));
  query.set('security', valueOr(vmess.tls, ''));
  query.set('sni', valueOr(vmess.sni, ''));
  query.set('fp', valueOr(vmess.fp, ''));
  query.set('alpn', valueOr(vmess.alpn, ''));
  query.set('insecure', valueOr(vmess.insecure, ''));
  const vmessNetwork = valueOr(vmess.net, '').toLowerCase();
  if (vmessNetwork === 'kcp') {
    query.set('seed', valueOr(vmess.path, ''));
  } else if (vmessNetwork === 'grpc') {
    query.set('mode', valueOr(vmess.type, ''));
    query.set('serviceName', valueOr(vmess.path, ''));
    query.set('authority', valueOr(vmess.host, ''));
  }

  const settings: XrayVmessSettings = {
    vnext: [{
      address: valueOr(vmess.add, ''),
      port: parsePort(valueOr(vmess.port, '0')),
      users: [{
        id: valueOr(vmess.id, ''),
        alterId: 0,
        security: valueOr(vmess.scy, 'auto')
      }]
    }]
  };
  const outbound: XrayOutbound = {
    protocol: 'vmess',
    tag: 'proxy',
    settings,
    streamSettings: buildStreamSettings(query, '')
  };
  return makeSuccess('vmess', valueOr(vmess.ps, ''), outbound);
}

function parseVmessAeadLink(input: string): ShareLinkParseResult {
  const parsed = parseUrlStyleShareLink(input, 'vmess');
  if (parsed.userInfo.length === 0) {
    return makeFailure('VMess 链接缺少用户 ID。', 'vmess');
  }
  const settings: XrayVmessSettings = {
    vnext: [{
      address: parsed.host,
      port: parsed.port,
      users: [{
        id: parsed.userInfo,
        alterId: 0,
        security: queryValue(parsed.query, 'encryption', queryValue(parsed.query, 'security', 'auto'))
      }]
    }]
  };
  const outbound: XrayOutbound = {
    protocol: 'vmess',
    tag: 'proxy',
    settings,
    streamSettings: buildStreamSettings(parsed.query, '')
  };
  return makeSuccess('vmess', defaultShareName(parsed.fragment), outbound);
}

function parseTrojanLink(input: string): ShareLinkParseResult {
  const parsed = parseUrlStyleShareLink(input, 'trojan');
  if (parsed.userInfo.length === 0) {
    return makeFailure('Trojan 链接缺少密码。', 'trojan');
  }

  const server: XrayTrojanServer = {
    address: parsed.host,
    port: parsed.port,
    password: parsed.userInfo
  };
  const flow = queryValue(parsed.query, 'flow', '');
  if (flow.length > 0) {
    server.flow = flow;
  }

  const settings: XrayTrojanSettings = {
    servers: [server]
  };

  const outbound: XrayOutbound = {
    protocol: 'trojan',
    tag: 'proxy',
    settings,
    streamSettings: buildStreamSettings(parsed.query, 'tls')
  };
  return makeSuccess('trojan', defaultShareName(parsed.fragment), outbound);
}

function parseShadowsocksLink(input: string): ShareLinkParseResult {
  return parseShadowsocksSip002(input) ?? parseShadowsocksLegacy(input);
}

function parseShadowsocksSip002(input: string): ShareLinkParseResult | null {
  const parsed = tryParseUrlStyleShareLink(input, 'ss');
  if (parsed === null) {
    return null;
  }

  let methodPassword = parsed.userInfo;
  if (methodPassword.indexOf(':') < 0) {
    methodPassword = decodeBase64ToUtf8(methodPassword);
  }
  const splitIndex = methodPassword.indexOf(':');
  if (splitIndex <= 0) {
    return makeFailure('Shadowsocks 链接缺少加密方法或密码。', 'shadowsocks');
  }

  return makeShadowsocksResult(
    methodPassword.substring(0, splitIndex).toLowerCase(),
    methodPassword.substring(splitIndex + 1),
    parsed.host,
    parsed.port,
    defaultShareName(parsed.fragment),
    parsed.query,
    input
  );
}

function parseShadowsocksLegacy(input: string): ShareLinkParseResult {
  let body = input.substring('ss://'.length);
  let fragment = '';
  const fragmentIndex = body.indexOf('#');
  if (fragmentIndex >= 0) {
    fragment = safeDecodeURIComponent(body.substring(fragmentIndex + 1));
    body = body.substring(0, fragmentIndex);
  }
  let decoded = decodeBase64ToUtf8(body);
  if (decoded.endsWith('/')) {
    decoded = decoded.substring(0, decoded.length - 1);
  }
  const atIndex = decoded.lastIndexOf('@');
  const splitIndex = decoded.indexOf(':');
  const portIndex = decoded.lastIndexOf(':');
  if (splitIndex <= 0 || atIndex <= splitIndex || portIndex <= atIndex) {
    return makeFailure('Shadowsocks legacy 链接格式不正确。', 'shadowsocks');
  }

  return makeShadowsocksResult(
    decoded.substring(0, splitIndex).toLowerCase(),
    decoded.substring(splitIndex + 1, atIndex),
    decoded.substring(atIndex + 1, portIndex).replace('[', '').replace(']', ''),
    parsePort(decoded.substring(portIndex + 1)),
    fragment,
    new Map<string, string>(),
    input
  );
}

function makeShadowsocksResult(method: string, password: string, host: string, port: number, name: string, query: Map<string, string>, input: string): ShareLinkParseResult {
  const streamQuery = new Map<string, string>();
  const plugin = queryValue(query, 'plugin', '');
  if (plugin.indexOf('obfs=http') >= 0) {
    streamQuery.set('type', 'tcp');
    streamQuery.set('headerType', 'http');
    streamQuery.set('host', getPluginValue(plugin, 'obfs-host'));
    streamQuery.set('path', getPluginValue(plugin, 'path'));
  } else {
    streamQuery.set('type', queryValue(query, 'type', 'tcp'));
    streamQuery.set('host', queryValue(query, 'host', ''));
    streamQuery.set('path', queryValue(query, 'path', ''));
    streamQuery.set('security', queryValue(query, 'security', ''));
    streamQuery.set('headerType', queryValue(query, 'headerType', 'none'));
    streamQuery.set('seed', queryValue(query, 'seed', ''));
    streamQuery.set('mtu', queryValue(query, 'mtu', ''));
    streamQuery.set('tti', queryValue(query, 'tti', ''));
    streamQuery.set('fm', queryValue(query, 'fm', ''));
    streamQuery.set('mode', queryValue(query, 'mode', ''));
    streamQuery.set('extra', queryValue(query, 'extra', ''));
    streamQuery.set('serviceName', queryValue(query, 'serviceName', ''));
    streamQuery.set('authority', queryValue(query, 'authority', ''));
  }

  const settings: XrayShadowsocksSettings = {
    servers: [{
      address: host,
      port,
      method,
      password
    }]
  };
  const outbound: XrayOutbound = {
    protocol: 'shadowsocks',
    tag: 'proxy',
    settings,
    streamSettings: buildStreamSettings(streamQuery, '')
  };
  return makeSuccess('shadowsocks', name.length > 0 ? name : deriveNameFromRaw(input), outbound);
}

function parseSocksLink(input: string, scheme: string): ShareLinkParseResult {
  const parsed = parseOptionalUserShareLink(input, scheme);
  const server: XrayGenericServer = {
    address: parsed.host,
    port: parsed.port
  };
  const user = parseGenericUser(parsed.userInfo);
  if (user !== null) {
    server.users = [user];
  }

  const outbound: XrayOutbound = {
    protocol: 'socks',
    tag: 'proxy',
    settings: {
      servers: [server]
    }
  };
  return makeSuccess('socks', defaultShareName(parsed.fragment), outbound);
}

function parseHttpProxyLink(input: string, scheme: string): ShareLinkParseResult {
  const parsed = parseOptionalUserShareLink(input, scheme);
  const server: XrayGenericServer = {
    address: parsed.host,
    port: parsed.port
  };
  const user = parseGenericUser(parsed.userInfo);
  if (user !== null) {
    server.users = [user];
  }

  const outbound: XrayOutbound = {
    protocol: 'http',
    tag: 'proxy',
    settings: {
      servers: [server]
    }
  };
  return makeSuccess('http', defaultShareName(parsed.fragment), outbound);
}

function parseWireguardLink(input: string): ShareLinkParseResult {
  const parsed = parseOptionalUserShareLink(input, 'wireguard');
  if (parsed.userInfo.length === 0) {
    return makeFailure('WireGuard 链接缺少私钥。', 'wireguard');
  }
  const publicKey = queryValue(parsed.query, 'publickey', queryValue(parsed.query, 'publicKey', ''));
  if (publicKey.length === 0) {
    return makeFailure('WireGuard 链接缺少 publickey。', 'wireguard');
  }

  const peer: XrayWireguardPeer = {
    publicKey,
    endpoint: formatEndpoint(parsed.host, parsed.port)
  };
  const preSharedKey = queryValue(parsed.query, 'presharedkey', queryValue(parsed.query, 'preSharedKey', ''));
  if (preSharedKey.length > 0) {
    peer.preSharedKey = preSharedKey;
  }

  const settings: XrayWireguardSettings = {
    secretKey: parsed.userInfo,
    address: splitCsvWithDefault(queryValue(parsed.query, 'address', ''), '172.16.0.2/32'),
    peers: [peer]
  };
  const mtu = parseOptionalPositiveInt(queryValue(parsed.query, 'mtu', ''));
  if (mtu > 0) {
    settings.mtu = mtu;
  }
  const reserved = parseNumberCsv(queryValue(parsed.query, 'reserved', ''));
  if (reserved.length > 0) {
    settings.reserved = reserved;
  }

  const outbound: XrayOutbound = {
    protocol: 'wireguard',
    tag: 'proxy',
    settings
  };
  return makeSuccess('wireguard', defaultShareName(parsed.fragment), outbound);
}

function parseHysteria2Link(input: string): ShareLinkParseResult {
  const scheme = input.toLowerCase().startsWith('hy2://') ? 'hy2' : 'hysteria2';
  const parsed = parseOptionalUserShareLink(input, scheme);
  if (parsed.userInfo.length === 0) {
    return makeFailure('Hysteria2 链接缺少认证密码。', 'hysteria2');
  }

  const server: XrayHysteria2Server = {
    address: parsed.host,
    port: parsed.port,
    password: parsed.userInfo
  };
  const sni = queryValue(parsed.query, 'sni', '');
  if (sni.length > 0) {
    server.sni = sni;
  }
  const alpn = queryValue(parsed.query, 'alpn', '');
  if (alpn.length > 0) {
    server.alpn = alpn;
  }
  const obfsPassword = queryValue(parsed.query, 'obfs-password', '');
  if (obfsPassword.length > 0) {
    server.obfsPassword = obfsPassword;
  }
  const portHopping = queryValue(parsed.query, 'mport', '');
  if (portHopping.length > 0) {
    server.portHopping = portHopping;
    const portHoppingInterval = queryValue(parsed.query, 'mportHopInt', '');
    if (portHoppingInterval.length > 0) {
      server.portHoppingInterval = portHoppingInterval;
    }
  }
  const pinSHA256 = queryValue(parsed.query, 'pinSHA256', '');
  if (pinSHA256.length > 0) {
    server.pinSHA256 = pinSHA256;
  }
  const insecure = queryValue(parsed.query, 'insecure', '');
  if (insecure.length > 0) {
    server.insecure = insecure === '1' || insecure.toLowerCase() === 'true';
  }

  const outbound: XrayOutbound = {
    protocol: 'hysteria2',
    tag: 'proxy',
    settings: {
      servers: [server]
    }
  };
  return makeSuccess('hysteria2', defaultShareName(parsed.fragment), outbound);
}

function tryParseUrlStyleShareLink(input: string, scheme: string): ParsedShareUrl | null {
  try {
    return parseUrlStyleShareLink(input, scheme);
  } catch (error) {
    return null;
  }
}

function parseOptionalUserShareLink(input: string, scheme: string): ParsedShareUrl {
  const prefix = `${scheme}://`;
  let body = input.substring(prefix.length);
  let fragment = '';
  const fragmentIndex = body.indexOf('#');
  if (fragmentIndex >= 0) {
    fragment = safeDecodeURIComponent(body.substring(fragmentIndex + 1));
    body = body.substring(0, fragmentIndex);
  }

  let rawQuery = '';
  const queryIndex = body.indexOf('?');
  if (queryIndex >= 0) {
    rawQuery = body.substring(queryIndex + 1);
    body = body.substring(0, queryIndex);
  }

  const atIndex = body.lastIndexOf('@');
  const userInfo = atIndex >= 0 ? safeDecodeURIComponent(body.substring(0, atIndex)) : '';
  const target = atIndex >= 0 ? body.substring(atIndex + 1) : body;
  const hostPort = parseHostPort(target);
  return {
    userInfo,
    host: hostPort.host,
    port: hostPort.port,
    query: parseQuery(rawQuery),
    fragment
  };
}

function parseUrlStyleShareLink(input: string, scheme: string): ParsedShareUrl {
  const prefix = `${scheme}://`;
  let body = input.substring(prefix.length);
  let fragment = '';
  const fragmentIndex = body.indexOf('#');
  if (fragmentIndex >= 0) {
    fragment = safeDecodeURIComponent(body.substring(fragmentIndex + 1));
    body = body.substring(0, fragmentIndex);
  }

  let rawQuery = '';
  const queryIndex = body.indexOf('?');
  if (queryIndex >= 0) {
    rawQuery = body.substring(queryIndex + 1);
    body = body.substring(0, queryIndex);
  }

  const atIndex = body.lastIndexOf('@');
  if (atIndex < 0) {
    throw new Error(`${scheme} 链接缺少用户信息或服务器地址。`);
  }

  const userInfo = safeDecodeURIComponent(body.substring(0, atIndex));
  const hostPort = parseHostPort(body.substring(atIndex + 1));
  return {
    userInfo,
    host: hostPort.host,
    port: hostPort.port,
    query: parseQuery(rawQuery),
    fragment
  };
}

function parseWireguardConfigDocument(input: string): WireguardConfigDocument {
  const interfaceParams = new Map<string, string>();
  const peerParams = new Map<string, string>();
  let currentSection = '';
  const lines = input.split('\n');

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index].trim();
    if (line.length === 0 || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }

    const lower = line.toLowerCase();
    if (lower === '[interface]') {
      currentSection = 'interface';
      continue;
    }
    if (lower === '[peer]') {
      currentSection = 'peer';
      continue;
    }

    const equalsIndex = line.indexOf('=');
    if (equalsIndex <= 0 || currentSection.length === 0) {
      continue;
    }
    const key = line.substring(0, equalsIndex).trim().toLowerCase();
    const value = line.substring(equalsIndex + 1).trim();
    if (key.length === 0 || value.length === 0) {
      continue;
    }

    if (currentSection === 'interface') {
      interfaceParams.set(key, value);
    } else if (currentSection === 'peer') {
      peerParams.set(key, value);
    }
  }

  return {
    interfaceParams,
    peerParams
  };
}

function mapValue(map: Map<string, string>, key: string): string {
  return map.get(key) ?? '';
}

function parseHostPort(value: string): HostPort {
  let target = value;
  const slashIndex = target.indexOf('/');
  if (slashIndex >= 0) {
    target = target.substring(0, slashIndex);
  }

  if (target.startsWith('[')) {
    const endIndex = target.indexOf(']');
    if (endIndex < 0) {
      throw new Error('IPv6 地址缺少右方括号。');
    }
    const portPrefix = target.substring(endIndex + 1, endIndex + 2);
    if (portPrefix !== ':') {
      throw new Error('服务器端口格式不正确。');
    }
    return {
      host: target.substring(1, endIndex),
      port: parsePort(target.substring(endIndex + 2))
    };
  }

  const portIndex = target.lastIndexOf(':');
  if (portIndex <= 0) {
    throw new Error('服务器地址缺少端口。');
  }
  return {
    host: safeDecodeURIComponent(target.substring(0, portIndex)),
    port: parsePort(target.substring(portIndex + 1))
  };
}

function parsePort(rawPort: string): number {
  const port = Number(rawPort);
  if (rawPort.length === 0 || port < 1 || port > 65535 || Math.floor(port) !== port) {
    throw new Error('服务器端口必须是 1-65535 的整数。');
  }
  return port;
}

function parseQuery(rawQuery: string): Map<string, string> {
  const result = new Map<string, string>();
  if (rawQuery.length === 0) {
    return result;
  }

  const pairs = rawQuery.split('&');
  for (let index = 0; index < pairs.length; index++) {
    const pair = pairs[index];
    if (pair.length === 0) {
      continue;
    }
    const equalIndex = pair.indexOf('=');
    const rawKey = equalIndex >= 0 ? pair.substring(0, equalIndex) : pair;
    const rawValue = equalIndex >= 0 ? pair.substring(equalIndex + 1) : '';
    const key = safeDecodeURIComponent(rawKey);
    if (key.length > 0) {
      result.set(key, safeDecodeURIComponent(rawValue));
    }
  }
  return result;
}

function buildStreamSettings(query: Map<string, string>, defaultSecurity: string): XrayStreamSettings {
  let network = queryValue(query, 'type', 'tcp').toLowerCase();
  if (network === 'http') {
    network = 'h2';
  }

  const host = queryValue(query, 'host', '');
  const path = queryValue(query, 'path', '');
  const headerType = queryValue(query, 'headerType', 'none');
  const stream: XrayStreamSettings = {
    network
  };
  let derivedSni = '';

  if (network === 'ws') {
    stream.wsSettings = {
      path: path.length > 0 ? path : '/',
      headers: {
        Host: host
      }
    };
    derivedSni = firstCsvValue(host);
  } else if (network === 'kcp') {
    const kcpSettings: XrayKcpSettings = {};
    const mtu = parseOptionalPositiveInt(queryValue(query, 'mtu', ''));
    const tti = parseOptionalPositiveInt(queryValue(query, 'tti', ''));
    if (mtu > 0) {
      kcpSettings.mtu = mtu;
    }
    if (tti > 0) {
      kcpSettings.tti = tti;
    }
    stream.kcpSettings = kcpSettings;
    stream.finalmask = buildKcpFinalMask(headerType, host, queryValue(query, 'seed', path));
    derivedSni = host;
  } else if (network === 'httpupgrade') {
    stream.httpupgradeSettings = {
      path: path.length > 0 ? path : '/',
      host
    };
    derivedSni = firstCsvValue(host);
  } else if (network === 'xhttp') {
    const xhttpSettings: XrayXhttpSettings = {
      path: path.length > 0 ? path : '/',
      host
    };
    const mode = queryValue(query, 'mode', '');
    if (mode.length > 0) {
      xhttpSettings.mode = mode;
    }
    const extra = parseOptionalJsonObject(queryValue(query, 'extra', ''));
    if (extra !== null) {
      xhttpSettings.extra = extra;
    }
    stream.xhttpSettings = xhttpSettings;
    derivedSni = firstCsvValue(host);
  } else if (network === 'h2') {
    stream.httpSettings = {
      host: splitCsv(host),
      path: path.length > 0 ? path : '/'
    };
    derivedSni = firstCsvValue(host);
  } else if (network === 'grpc') {
    const authority = queryValue(query, 'authority', '');
    const grpcSettings: XrayGrpcSettings = {
      serviceName: queryValue(query, 'serviceName', ''),
      multiMode: queryValue(query, 'mode', '') === 'multi',
      idle_timeout: 60,
      health_check_timeout: 20
    };
    if (authority.length > 0) {
      grpcSettings.authority = authority;
    }
    stream.grpcSettings = grpcSettings;
    derivedSni = authority;
  } else {
    stream.network = 'tcp';
    stream.tcpSettings = buildTcpSettings(headerType, host, path);
    derivedSni = headerType === 'http' ? firstCsvValue(host) : host;
  }

  applySecuritySettings(stream, query, defaultSecurity, derivedSni);
  const finalMask = parseOptionalJsonContainer(queryValue(query, 'fm', ''));
  if (finalMask !== null) {
    stream.finalmask = finalMask;
  }
  return stream;
}

function buildTcpSettings(headerType: string, host: string, path: string): XrayTcpSettings {
  const header: XrayTcpHeader = {
    type: headerType === 'http' ? 'http' : 'none'
  };
  if (header.type === 'http') {
    header.request = {
      path: splitCsvWithDefault(path, '/'),
      headers: {
        Host: splitCsv(host)
      }
    };
  }
  return {
    header
  };
}

function applySecuritySettings(stream: XrayStreamSettings, query: Map<string, string>, defaultSecurity: string, derivedSni: string): void {
  const security = queryValue(query, 'security', defaultSecurity).toLowerCase();
  if (security !== 'tls' && security !== 'reality') {
    return;
  }

  const tlsSettings = buildTlsSettings(query, security, derivedSni);
  stream.security = security;
  if (security === 'tls') {
    stream.tlsSettings = tlsSettings;
  } else {
    stream.realitySettings = tlsSettings;
  }
}

function buildTlsSettings(query: Map<string, string>, security: string, derivedSni: string): XrayTlsSettings {
  const settings: XrayTlsSettings = {
    allowInsecure: queryBooleanValue(query, ['insecure', 'allowInsecure', 'allow_insecure'], false)
  };

  const sni = queryValue(query, 'sni', derivedSni);
  if (sni.length > 0) {
    settings.serverName = sni;
  }
  const fingerprint = queryValue(query, 'fp', '');
  if (fingerprint.length > 0) {
    settings.fingerprint = fingerprint;
  }
  const alpn = splitCsv(queryValue(query, 'alpn', ''));
  if (alpn.length > 0) {
    settings.alpn = alpn;
  }
  const echConfigList = queryValue(query, 'ech', '');
  if (echConfigList.length > 0) {
    settings.echConfigList = echConfigList;
  }
  const pinnedPeerCertSha256 = queryValue(query, 'pcs', '');
  if (pinnedPeerCertSha256.length > 0) {
    settings.pinnedPeerCertSha256 = pinnedPeerCertSha256;
    settings.allowInsecure = false;
  }
  const publicKey = queryValue(query, 'pbk', '');
  if (publicKey.length > 0) {
    settings.publicKey = publicKey;
  }
  const shortId = queryValue(query, 'sid', '');
  if (shortId.length > 0) {
    settings.shortId = shortId;
  }
  const spiderX = queryValue(query, 'spx', '');
  if (spiderX.length > 0) {
    settings.spiderX = spiderX;
  }
  const mldsa65Verify = queryValue(query, 'pqv', '');
  if (mldsa65Verify.length > 0) {
    settings.mldsa65Verify = mldsa65Verify;
  }
  if (security === 'reality') {
    settings.show = false;
  }
  return settings;
}

function queryValue(query: Map<string, string>, key: string, fallback: string): string {
  const value = query.get(key);
  if (value === undefined || value.length === 0) {
    return fallback;
  }
  return value;
}

function queryBooleanValue(query: Map<string, string>, keys: Array<string>, fallback: boolean): boolean {
  let hasFalseValue = false;
  for (let index = 0; index < keys.length; index++) {
    const value = query.get(keys[index]);
    if (value === undefined || value.length === 0) {
      continue;
    }
    const normalized = value.toLowerCase();
    if (normalized === '1' || normalized === 'true') {
      return true;
    }
    if (normalized === '0' || normalized === 'false') {
      hasFalseValue = true;
    }
  }
  return hasFalseValue ? false : fallback;
}

function splitCsv(value: string): Array<string> {
  const result: Array<string> = [];
  if (value.length === 0) {
    return result;
  }

  const values = value.split(',');
  for (let index = 0; index < values.length; index++) {
    const item = values[index].trim();
    if (item.length > 0) {
      result.push(item);
    }
  }
  return result;
}

function splitCsvWithDefault(value: string, fallback: string): Array<string> {
  const values = splitCsv(value);
  if (values.length > 0) {
    return values;
  }
  return [fallback];
}

function firstCsvValue(value: string): string {
  const values = splitCsv(value);
  return values.length > 0 ? values[0] : '';
}

function parseOptionalJsonObject(value: string): Object | null {
  if (value.length === 0) {
    return null;
  }
  try {
    return JSON.parse(value) as Object;
  } catch (error) {
    return null;
  }
}

function parseOptionalJsonContainer(value: string): Object | null {
  const parsed = parseOptionalJsonObject(value);
  if (parsed === null || typeof parsed !== 'object') {
    return null;
  }
  return parsed;
}

function getPluginValue(plugin: string, key: string): string {
  const pairs = plugin.split(';');
  const prefix = `${key}=`;
  for (let index = 0; index < pairs.length; index++) {
    const pair = pairs[index];
    if (pair.startsWith(prefix)) {
      return pair.substring(prefix.length);
    }
  }
  return '';
}

function deriveNameFromRaw(input: string): string {
  const fragmentIndex = input.indexOf('#');
  if (fragmentIndex >= 0) {
    return safeDecodeURIComponent(input.substring(fragmentIndex + 1));
  }
  return '';
}

function parseGenericUser(userInfo: string): XrayGenericUser | null {
  if (userInfo.length === 0) {
    return null;
  }
  let value = userInfo;
  if (value.indexOf(':') < 0) {
    try {
      value = decodeBase64ToUtf8(value);
    } catch (error) {
      value = userInfo;
    }
  }
  const splitIndex = value.indexOf(':');
  if (splitIndex < 0) {
    return {
      user: value,
      pass: ''
    };
  }
  return {
    user: value.substring(0, splitIndex),
    pass: value.substring(splitIndex + 1)
  };
}

function formatEndpoint(host: string, port: number): string {
  if (host.indexOf(':') >= 0 && !host.startsWith('[')) {
    return `[${host}]:${port}`;
  }
  return `${host}:${port}`;
}

function parseOptionalPositiveInt(value: string): number {
  if (value.length === 0) {
    return 0;
  }
  const parsed = Number(value);
  if (Number.isNaN(parsed) || parsed <= 0 || Math.floor(parsed) !== parsed) {
    return 0;
  }
  return parsed;
}

function parseNumberCsv(value: string): Array<number> {
  const result: Array<number> = [];
  const parts = splitCsv(value);
  for (let index = 0; index < parts.length; index++) {
    const parsed = Number(parts[index]);
    if (!Number.isNaN(parsed) && Math.floor(parsed) === parsed) {
      result.push(parsed);
    }
  }
  return result;
}

function empty(value: string | undefined): boolean {
  return value === undefined || value.length === 0;
}

function valueOr(value: string | undefined, fallback: string): string {
  if (value === undefined || value.length === 0) {
    return fallback;
  }
  return value;
}

function safeDecodeURIComponent(value: string): string {
  try {
    return decodeURIComponent(value.split('+').join('%20'));
  } catch (error) {
    return value;
  }
}

function stringifyError(error: Error): string {
  if (error.message !== undefined && error.message.length > 0) {
    return error.message;
  }
  return JSON.stringify(error);
}

function formatHostPort(host: string, port: number): string {
  if (host.indexOf(':') >= 0 && !host.startsWith('[')) {
    return `[${host}]:${port}`;
  }
  return `${host}:${port}`;
}

function formatQueryParams(params: Map<string, string>): string {
  if (params.size === 0) {
    return '';
  }
  const parts: Array<string> = [];
  params.forEach((value, key) => {
    parts.push(`${key}=${encodeURIComponent(value)}`);
  });
  return `?${parts.join('&')}`;
}

function formatUserInfo(value: string): string {
  return encodeURIComponent(value);
}

function normalizeHysteria2PortHoppingInterval(value: string | undefined): string {
  const rawInterval = value === undefined ? '' : value.trim();
  if (rawInterval.length === 0) {
    return '';
  }
  const singleValue = Number(rawInterval);
  if (!Number.isNaN(singleValue) && Math.floor(singleValue) === singleValue) {
    return singleValue < 5 ? '' : String(singleValue);
  }
  const parts = rawInterval.split('-');
  if (parts.length !== 2) {
    return '';
  }
  const start = Number(parts[0].trim());
  const end = Number(parts[1].trim());
  if (Number.isNaN(start) || Number.isNaN(end) || Math.floor(start) !== start || Math.floor(end) !== end) {
    return '';
  }
  const minStart = Math.max(5, start);
  const minEnd = Math.max(minStart, end);
  return String(Math.floor((minStart + minEnd) / 2));
}

function appendStreamSettingsToQuery(queryParams: Map<string, string>, stream?: XrayStreamSettings): void {
  if (!stream) return;
  const network = stream.network || 'tcp';
  queryParams.set('type', network === 'http' || network === 'h2' ? 'http' : network);

  const security = stream.security || 'none';
  queryParams.set('security', security);

  if (security === 'tls' || security === 'reality') {
    const tlsSettings = security === 'tls' ? stream.tlsSettings : stream.realitySettings;
    if (security === 'tls') {
      const insecureFlag = tlsSettings?.allowInsecure ? '1' : '0';
      queryParams.set('insecure', insecureFlag);
      queryParams.set('allowInsecure', insecureFlag);
    }
    if (tlsSettings) {
      if (tlsSettings.serverName) {
        queryParams.set('sni', tlsSettings.serverName);
      }
      if (tlsSettings.alpn && tlsSettings.alpn.length > 0) {
        queryParams.set('alpn', tlsSettings.alpn.join(','));
      }
      if (tlsSettings.fingerprint) {
        queryParams.set('fp', tlsSettings.fingerprint);
      }
      if (tlsSettings.echConfigList) {
        queryParams.set('ech', tlsSettings.echConfigList);
      }
      if (tlsSettings.pinnedPeerCertSha256) {
        queryParams.set('pcs', tlsSettings.pinnedPeerCertSha256);
      }
      if (tlsSettings.publicKey) {
        queryParams.set('pbk', tlsSettings.publicKey);
      }
      if (tlsSettings.shortId) {
        queryParams.set('sid', tlsSettings.shortId);
      }
      if (tlsSettings.spiderX) {
        queryParams.set('spx', tlsSettings.spiderX);
      }
      if (tlsSettings.mldsa65Verify) {
        queryParams.set('pqv', tlsSettings.mldsa65Verify);
      }
    }
  }

  if (stream.finalmask && (network !== 'kcp' || !isCanonicalKcpFinalMask(stream.finalmask))) {
    queryParams.set('fm', JSON.stringify(stream.finalmask));
  }

  if (network === 'ws' && stream.wsSettings) {
    if (stream.wsSettings.path) {
      queryParams.set('path', stream.wsSettings.path);
    }
    if (stream.wsSettings.headers?.Host) {
      queryParams.set('host', stream.wsSettings.headers.Host);
    }
  } else if (network === 'kcp') {
    const kcpParams = readKcpShareParamsFromFinalMask(stream.finalmask);
    queryParams.set('headerType', kcpParams.headerType);
    if (kcpParams.seed.length > 0) {
      queryParams.set('seed', kcpParams.seed);
    }
    if (kcpParams.host.length > 0) {
      queryParams.set('host', kcpParams.host);
    }
    if (stream.kcpSettings?.mtu !== undefined && stream.kcpSettings.mtu > 0) {
      queryParams.set('mtu', String(stream.kcpSettings.mtu));
    }
    if (stream.kcpSettings?.tti !== undefined && stream.kcpSettings.tti > 0) {
      queryParams.set('tti', String(stream.kcpSettings.tti));
    }
  } else if (network === 'httpupgrade' && stream.httpupgradeSettings) {
    if (stream.httpupgradeSettings.path) {
      queryParams.set('path', stream.httpupgradeSettings.path);
    }
    if (stream.httpupgradeSettings.host) {
      queryParams.set('host', stream.httpupgradeSettings.host);
    }
  } else if (network === 'grpc' && stream.grpcSettings) {
    if (stream.grpcSettings.serviceName) {
      queryParams.set('serviceName', stream.grpcSettings.serviceName);
    }
    if (stream.grpcSettings.authority) {
      queryParams.set('authority', stream.grpcSettings.authority);
    }
    if (stream.grpcSettings.multiMode) {
      queryParams.set('mode', 'multi');
    }
  } else if ((network === 'h2' || network === 'http') && stream.httpSettings) {
    if (stream.httpSettings.path) {
      queryParams.set('path', stream.httpSettings.path);
    }
    if (stream.httpSettings.host && stream.httpSettings.host.length > 0) {
      queryParams.set('host', stream.httpSettings.host.join(','));
    }
  } else if (network === 'xhttp' && stream.xhttpSettings) {
    if (stream.xhttpSettings.path) {
      queryParams.set('path', stream.xhttpSettings.path);
    }
    if (stream.xhttpSettings.host) {
      queryParams.set('host', stream.xhttpSettings.host);
    }
    if (stream.xhttpSettings.mode) {
      queryParams.set('mode', stream.xhttpSettings.mode);
    }
    if (stream.xhttpSettings.extra) {
      queryParams.set('extra', JSON.stringify(stream.xhttpSettings.extra));
    }
  } else if (network === 'tcp' && stream.tcpSettings?.header?.type === 'http') {
    queryParams.set('headerType', 'http');
    const tcpReq = stream.tcpSettings.header.request;
    if (tcpReq) {
      if (tcpReq.path && tcpReq.path.length > 0) {
        queryParams.set('path', tcpReq.path.join(','));
      }
      if (tcpReq.headers?.Host && tcpReq.headers.Host.length > 0) {
        queryParams.set('host', tcpReq.headers.Host.join(','));
      }
    }
  }
}

function formatVmess(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayVmessSettings;
  const server = settings?.vnext?.[0];
  const user = server?.users?.[0];
  if (!server || !user) {
    throw new Error('VMess settings 缺少服务器或用户配置。');
  }

  const stream = outbound.streamSettings;
  const network = stream?.network || 'tcp';
  const security = stream?.security || '';

  const vmessObj: VmessQrCode = {
    v: '2',
    ps: name,
    add: server.address,
    port: String(server.port),
    id: user.id,
    scy: user.security || 'auto',
    net: network,
    type: 'none',
    host: '',
    path: '',
    tls: security
  };

  if (security === 'tls' || security === 'reality') {
    const tlsSettings = security === 'tls' ? stream?.tlsSettings : stream?.realitySettings;
    if (tlsSettings) {
      if (tlsSettings.serverName) vmessObj.sni = tlsSettings.serverName;
      if (tlsSettings.allowInsecure) vmessObj.insecure = '1';
      if (tlsSettings.alpn && tlsSettings.alpn.length > 0) vmessObj.alpn = tlsSettings.alpn.join(',');
      if (tlsSettings.fingerprint) vmessObj.fp = tlsSettings.fingerprint;
    }
  }

  if (network === 'ws' && stream?.wsSettings) {
    vmessObj.path = stream.wsSettings.path || '/';
    vmessObj.host = stream.wsSettings.headers?.Host || '';
  } else if (network === 'kcp') {
    const kcpParams = readKcpShareParamsFromFinalMask(stream?.finalmask);
    vmessObj.type = kcpParams.headerType;
    vmessObj.host = kcpParams.host;
    vmessObj.path = kcpParams.seed;
  } else if (network === 'httpupgrade' && stream?.httpupgradeSettings) {
    vmessObj.path = stream.httpupgradeSettings.path || '/';
    vmessObj.host = stream.httpupgradeSettings.host || '';
  } else if (network === 'grpc' && stream?.grpcSettings) {
    vmessObj.path = stream.grpcSettings.serviceName || '';
    vmessObj.host = stream.grpcSettings.authority || '';
    vmessObj.type = stream.grpcSettings.multiMode ? 'multi' : 'gun';
  } else if ((network === 'h2' || network === 'http') && stream?.httpSettings) {
    vmessObj.net = 'h2';
    vmessObj.path = stream.httpSettings.path || '/';
    vmessObj.host = stream.httpSettings.host?.join(',') || '';
  } else if (network === 'tcp' && stream?.tcpSettings) {
    const header = stream.tcpSettings.header;
    vmessObj.type = header?.type || 'none';
    if (header?.type === 'http' && header.request) {
      vmessObj.path = header.request.path?.join(',') || '/';
      vmessObj.host = header.request.headers?.Host?.join(',') || '';
    }
  } else if (network === 'xhttp' && stream?.xhttpSettings) {
    vmessObj.path = stream.xhttpSettings.path || '/';
    vmessObj.host = stream.xhttpSettings.host || '';
    vmessObj.type = stream.xhttpSettings.mode || '';
  }

  const jsonStr = JSON.stringify(vmessObj);
  const base64Str = encodeUtf8ToBase64(jsonStr);
  return `vmess://${base64Str}`;
}

function formatVless(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayVlessSettings;
  const server = settings?.vnext?.[0];
  const user = server?.users?.[0];
  if (!server || !user) {
    throw new Error('VLESS settings 缺少服务器或用户配置。');
  }

  const queryParams = new Map<string, string>();
  queryParams.set('encryption', user.encryption || 'none');
  if (user.flow) {
    queryParams.set('flow', user.flow);
  }

  appendStreamSettingsToQuery(queryParams, outbound.streamSettings);

  const queryStr = formatQueryParams(queryParams);
  const hashStr = name.length > 0 ? `#${encodeURIComponent(name)}` : '';
  return `vless://${formatUserInfo(user.id)}@${formatHostPort(server.address, server.port)}${queryStr}${hashStr}`;
}

function formatTrojan(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayTrojanSettings;
  const server = settings?.servers?.[0];
  if (!server) {
    throw new Error('Trojan settings 缺少服务器配置。');
  }

  const queryParams = new Map<string, string>();
  if (server.flow) {
    queryParams.set('flow', server.flow);
  }

  appendStreamSettingsToQuery(queryParams, outbound.streamSettings);

  const queryStr = formatQueryParams(queryParams);
  const hashStr = name.length > 0 ? `#${encodeURIComponent(name)}` : '';
  return `trojan://${formatUserInfo(server.password)}@${formatHostPort(server.address, server.port)}${queryStr}${hashStr}`;
}

function formatShadowsocks(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayShadowsocksSettings;
  const server = settings?.servers?.[0];
  if (!server) {
    throw new Error('Shadowsocks settings 缺少服务器配置。');
  }

  const credentials = `${server.method}:${server.password}`;
  const base64Credentials = encodeUtf8ToBase64(credentials);

  const queryParams = new Map<string, string>();
  const stream = outbound.streamSettings;
  if (stream) {
    const network = stream.network || 'tcp';
    if (network === 'tcp' && stream.tcpSettings?.header?.type === 'http') {
      const host = stream.tcpSettings.header.request?.headers?.Host?.[0] || '';
      const path = stream.tcpSettings.header.request?.path?.[0] || '';
      queryParams.set('plugin', `obfs-local;obfs=http;obfs-host=${host};path=${path}`);
    }
  }

  const queryStr = formatQueryParams(queryParams);
  const hashStr = name.length > 0 ? `#${encodeURIComponent(name)}` : '';
  return `ss://${base64Credentials}@${formatHostPort(server.address, server.port)}${queryStr}${hashStr}`;
}

function formatSocks(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayServerSettings;
  const server = settings?.servers?.[0];
  if (!server) {
    throw new Error('Socks settings 缺少服务器配置。');
  }

  let userInfo = '';
  if (server.users && server.users.length > 0) {
    userInfo = `${encodeURIComponent(encodeUtf8ToBase64(`${server.users[0].user}:${server.users[0].pass}`))}@`;
  }
  const hashStr = name.length > 0 ? `#${encodeURIComponent(name)}` : '';
  return `socks://${userInfo}${formatHostPort(server.address, server.port)}${hashStr}`;
}

function formatHttp(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayServerSettings;
  const server = settings?.servers?.[0];
  if (!server) {
    throw new Error('HTTP settings 缺少服务器配置。');
  }

  let userInfo = '';
  if (server.users && server.users.length > 0) {
    userInfo = `${formatUserInfo(`${server.users[0].user}:${server.users[0].pass}`)}@`;
  }
  const hashStr = name.length > 0 ? `#${encodeURIComponent(name)}` : '';
  return `http://${userInfo}${formatHostPort(server.address, server.port)}${hashStr}`;
}

function formatWireguard(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayWireguardSettings;
  if (!settings) {
    throw new Error('WireGuard settings 缺少配置。');
  }
  const peer = settings.peers?.[0];
  if (!peer) {
    throw new Error('WireGuard settings 缺少 peer 配置。');
  }

  const queryParams = new Map<string, string>();
  queryParams.set('publickey', peer.publicKey);
  if (peer.preSharedKey) {
    queryParams.set('presharedkey', peer.preSharedKey);
  }
  if (settings.address && settings.address.length > 0) {
    queryParams.set('address', settings.address.join(','));
  }
  if (settings.mtu) {
    queryParams.set('mtu', String(settings.mtu));
  }
  if (settings.reserved && settings.reserved.length > 0) {
    queryParams.set('reserved', settings.reserved.join(','));
  }

  const endpoint = peer.endpoint;
  const queryStr = formatQueryParams(queryParams);
  const hashStr = name.length > 0 ? `#${encodeURIComponent(name)}` : '';
  return `wireguard://${formatUserInfo(settings.secretKey)}@${endpoint}${queryStr}${hashStr}`;
}

function formatHysteria2(outbound: XrayOutbound, name: string): string {
  const settings = outbound.settings as XrayHysteria2Settings;
  const server = settings?.servers?.[0];
  if (!server) {
    throw new Error('Hysteria2 settings 缺少服务器配置。');
  }

  const queryParams = new Map<string, string>();
  if (server.sni) {
    queryParams.set('sni', server.sni);
  }
  if (server.alpn) {
    queryParams.set('alpn', server.alpn);
  }
  if (server.insecure) {
    queryParams.set('insecure', '1');
  }
  if (server.obfsPassword) {
    queryParams.set('obfs', 'salamander');
    queryParams.set('obfs-password', server.obfsPassword);
  }
  if (server.portHopping) {
    queryParams.set('mport', server.portHopping);
    const interval = normalizeHysteria2PortHoppingInterval(server.portHoppingInterval);
    if (interval.length > 0) {
      queryParams.set('mportHopInt', interval);
    }
  }
  if (server.pinSHA256) {
    queryParams.set('pinSHA256', server.pinSHA256);
  }

  const queryStr = formatQueryParams(queryParams);
  const hashStr = name.length > 0 ? `#${encodeURIComponent(name)}` : '';
  return `hysteria2://${formatUserInfo(server.password)}@${formatHostPort(server.address, server.port)}${queryStr}${hashStr}`;
}

export function formatOutboundJsonToShareLink(outboundJson: string, name: string): string {
  try {
    const outbound = JSON.parse(outboundJson) as XrayOutbound;
    const protocol = outbound.protocol?.toLowerCase();
    if (protocol === 'vless') {
      return formatVless(outbound, name);
    }
    if (protocol === 'vmess') {
      return formatVmess(outbound, name);
    }
    if (protocol === 'trojan') {
      return formatTrojan(outbound, name);
    }
    if (protocol === 'shadowsocks') {
      return formatShadowsocks(outbound, name);
    }
    if (protocol === 'socks') {
      return formatSocks(outbound, name);
    }
    if (protocol === 'http') {
      return formatHttp(outbound, name);
    }
    if (protocol === 'wireguard') {
      return formatWireguard(outbound, name);
    }
    if (protocol === 'hysteria2') {
      return formatHysteria2(outbound, name);
    }
    return '';
  } catch (error) {
    return '';
  }
}
