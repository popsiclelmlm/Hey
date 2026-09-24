import { AppSettings } from './Profile';
import { VPN_DATA_SOCKS_HOST, VPN_DATA_SOCKS_PORT } from './XrayConfig';
import { coerceRealitySafeFingerprint } from './RealityFingerprint';

/**
 * sing-box 配置生成器（预览功能）。
 *
 * 把单个节点的 Xray outbound JSON 转换成 sing-box 的完整运行配置：
 *   本地 SOCKS(mixed) 入站（监听 VPN_DATA_SOCKS 端口，由 libheytun2socks.so 把 Harmony
 *   TUN fd 的流量转发进来——与 Xray 统一走 tun2socks 数据面，不用 tun 入站/OpenTun）+
 *   代理出站 + direct/dns 出站 + 基础路由（DNS 劫持、私网直连、其余走代理）+ 基础 DNS。
 *
 * 覆盖最常见协议：VLESS / VMess / Trojan / Shadowsocks / AnyTLS，传输 tcp/ws/grpc/http(upgrade)，
 * 安全 none/tls/reality。不支持的协议返回 ok=false（不抛异常），由调用方提示。
 *
 * 注意：节点凭据（地址/端口/UUID/密码/TLS）与 Xray 是同一份事实，这里只做"格式翻译"——
 * 字段名、结构、嵌套都按 sing-box schema 重新组织（见 README 里 VLESS 对照）。
 */

type JsonField = Object | string | number | boolean | undefined;
type JsonObject = Record<string, JsonField>;

export interface GeneratedSingboxConfig {
  ok: boolean;
  message: string;
  configJson: string;
}

// sing-box 分级日志文件名(落在 filesDir，与 Xray 的 xray-core.log 对齐)。
export const SINGBOX_CORE_LOG_FILE: string = 'singbox-core.log';

// ---- sing-box 输出 schema（仅声明用到的字段；可选字段为 undefined 时被 JSON.stringify 省略）----

interface SbUtls {
  enabled: boolean;
  fingerprint: string;
}

interface SbReality {
  enabled: boolean;
  public_key: string;
  short_id: string;
}

interface SbTls {
  enabled: boolean;
  server_name?: string;
  insecure?: boolean;
  alpn?: Array<string>;
  utls?: SbUtls;
  reality?: SbReality;
}

interface SbTransport {
  type: string;
  path?: string;
  headers?: Record<string, string>;
  service_name?: string;
  host?: Array<string>;
}

// Hysteria2 的 salamander 混淆。
interface SbHysteria2Obfs {
  type: string;
  password: string;
}

interface SbOutbound {
  type: string;
  tag: string;
  server?: string;
  server_port?: number;
  uuid?: string;
  flow?: string;
  security?: string;
  alter_id?: number;
  password?: string;
  method?: string;
  network?: string;
  packet_encoding?: string;
  congestion_control?: string;
  udp_relay_mode?: string;
  up_mbps?: number;
  down_mbps?: number;
  obfs?: SbHysteria2Obfs;
  tls?: SbTls;
  transport?: SbTransport;
}

interface SbInbound {
  type: string;
  tag: string;
  listen?: string;
  listen_port?: number;
  sniff?: boolean;
  sniff_override_destination?: boolean;
}

interface SbDnsServer {
  tag: string;
  address: string;
  detour?: string;
}

interface SbDnsRule {
  domain?: Array<string>;
  server: string;
}

interface SbDns {
  servers: Array<SbDnsServer>;
  rules?: Array<SbDnsRule>;
  final?: string;
  strategy?: string;
}

interface SbRouteRule {
  protocol?: string;
  outbound?: string;
  ip_is_private?: boolean;
}

interface SbRoute {
  rules: Array<SbRouteRule>;
  final: string;
  auto_detect_interface: boolean;
}

interface SbLog {
  level: string;
  timestamp: boolean;
  output?: string;
}

interface SbConfig {
  log: SbLog;
  dns: SbDns;
  inbounds: Array<SbInbound>;
  outbounds: Array<SbOutbound>;
  route: SbRoute;
}

// ---- JSON 读取辅助（沿用 XrayConfig.ets 的 ArkTS 惯用法）----

function asObject(value: JsonField): JsonObject | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  return value as JsonObject;
}

function asString(value: JsonField): string {
  return typeof value === 'string' ? value : '';
}

// sing-box 1.12 没有证书哈希钉住选项（pinSHA256 / pinnedPeerCertSha256 都无处可放）。钉住存在时
// 不下发 insecure，退回常规 CA 校验：宁可握手失败，也不在零校验下连接（与 Xray 侧
// disableAllowInsecureWhenPinned 同一规则）。
function hasPinnedCertificate(value: JsonField): boolean {
  return asString(value).trim().length > 0;
}

function asNumber(value: JsonField): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

function asStringArray(value: JsonField): Array<string> {
  if (!Array.isArray(value)) {
    return [];
  }
  const result = new Array<string>();
  for (let index = 0; index < value.length; index++) {
    const item = value[index] as JsonField;
    if (typeof item === 'string' && item.length > 0) {
      result.push(item);
    }
  }
  return result;
}

function firstObject(value: JsonField): JsonObject | undefined {
  if (!Array.isArray(value) || value.length === 0) {
    return undefined;
  }
  return asObject(value[0] as JsonField);
}

// ---- TLS / 传输转换 ----

function buildTls(stream: JsonObject): SbTls | undefined {
  const security = asString(stream['security']);
  if (security === 'tls' || security === 'xtls') {
    const tlsSettings = asObject(stream['tlsSettings']) ?? asObject(stream['xtlsSettings']) ?? {};
    const tls: SbTls = { enabled: true };
    const sni = asString(tlsSettings['serverName']);
    if (sni.length > 0) {
      tls.server_name = sni;
    }
    if (tlsSettings['allowInsecure'] === true && !hasPinnedCertificate(tlsSettings['pinnedPeerCertSha256'])) {
      tls.insecure = true;
    }
    const alpn = asStringArray(tlsSettings['alpn']);
    if (alpn.length > 0) {
      tls.alpn = alpn;
    }
    const fingerprint = asString(tlsSettings['fingerprint']);
    if (fingerprint.length > 0) {
      tls.utls = { enabled: true, fingerprint };
    }
    return tls;
  }
  if (security === 'reality') {
    const realitySettings = asObject(stream['realitySettings']) ?? {};
    const tls: SbTls = { enabled: true };
    const sni = asString(realitySettings['serverName']);
    if (sni.length > 0) {
      tls.server_name = sni;
    }
    // reality 必须有 utls 指纹；chrome 系指纹的 X25519MLKEM768 会导致 REALITY 握手失败，
    // 统一走 coerceRealitySafeFingerprint 兼容处理(详见 RealityFingerprint.ets)。
    tls.utls = { enabled: true, fingerprint: coerceRealitySafeFingerprint(asString(realitySettings['fingerprint'])) };
    tls.reality = {
      enabled: true,
      public_key: asString(realitySettings['publicKey']),
      short_id: asString(realitySettings['shortId'])
    };
    return tls;
  }
  return undefined;
}

// anytls 这类把 TLS 字段内联在 server 对象（而非 streamSettings）里的协议：直接从 server 组 sing-box TLS。
// anytls 协议本身即「any TLS」，链路恒走 TLS，所以这里恒为 enabled。
function buildServerTls(server: JsonObject): SbTls {
  const tls: SbTls = { enabled: true };
  const sni = asString(server['sni']);
  if (sni.length > 0) {
    tls.server_name = sni;
  }
  if (server['insecure'] === true && !hasPinnedCertificate(server['pinSHA256'])) {
    tls.insecure = true;
  }
  const alpn = splitCsv(asString(server['alpn']));
  if (alpn.length > 0) {
    tls.alpn = alpn;
  }
  const fingerprint = asString(server['fingerprint']);
  if (fingerprint.length > 0) {
    tls.utls = { enabled: true, fingerprint };
  }
  return tls;
}

function splitCsv(value: string): Array<string> {
  const result = new Array<string>();
  if (value.length === 0) {
    return result;
  }
  const parts = value.split(',');
  for (let index = 0; index < parts.length; index++) {
    const item = parts[index].trim();
    if (item.length > 0) {
      result.push(item);
    }
  }
  return result;
}

function stripEarlyData(path: string): string {
  const queryIndex = path.indexOf('?');
  return queryIndex >= 0 ? path.substring(0, queryIndex) : path;
}

function buildTransport(stream: JsonObject): SbTransport | undefined {
  const network = asString(stream['network']);
  if (network === 'ws' || network === 'websocket') {
    const ws = asObject(stream['wsSettings']) ?? {};
    const transport: SbTransport = { type: 'ws' };
    const path = asString(ws['path']);
    transport.path = path.length > 0 ? stripEarlyData(path) : '/';
    const headers = asObject(ws['headers']);
    const host = headers !== undefined ? asString(headers['Host']) : asString(ws['host']);
    if (host.length > 0) {
      transport.headers = { 'Host': host };
    }
    return transport;
  }
  if (network === 'grpc') {
    const grpc = asObject(stream['grpcSettings']) ?? {};
    const transport: SbTransport = { type: 'grpc' };
    const serviceName = asString(grpc['serviceName']);
    if (serviceName.length > 0) {
      transport.service_name = serviceName;
    }
    return transport;
  }
  if (network === 'h2' || network === 'http') {
    const http = asObject(stream['httpSettings']) ?? {};
    const transport: SbTransport = { type: 'http' };
    const path = asString(http['path']);
    if (path.length > 0) {
      transport.path = path;
    }
    const hosts = asStringArray(http['host']);
    if (hosts.length > 0) {
      transport.host = hosts;
    }
    return transport;
  }
  if (network === 'httpupgrade') {
    const hu = asObject(stream['httpupgradeSettings']) ?? {};
    const transport: SbTransport = { type: 'httpupgrade' };
    const path = asString(hu['path']);
    if (path.length > 0) {
      transport.path = path;
    }
    const host = asString(hu['host']);
    if (host.length > 0) {
      transport.host = [host];
    }
    return transport;
  }
  // tcp / raw（含 http obfs header，sing-box 无直接对应，按裸 tcp 处理）→ 无 transport。
  return undefined;
}

// ---- 各协议 outbound 转换 ----

function convertOutbound(outbound: JsonObject): SbOutbound | null {
  const protocol = asString(outbound['protocol']).toLowerCase();
  const settings = asObject(outbound['settings']) ?? {};
  const stream = asObject(outbound['streamSettings']) ?? {};
  const tls = buildTls(stream);
  const transport = buildTransport(stream);

  if (protocol === 'vless') {
    const server = firstObject(settings['vnext']);
    if (server === undefined) {
      return null;
    }
    const user = firstObject(server['users']);
    if (user === undefined) {
      return null;
    }
    const out: SbOutbound = {
      type: 'vless',
      tag: 'proxy',
      server: asString(server['address']),
      server_port: asNumber(server['port']),
      uuid: asString(user['id']),
      packet_encoding: 'xudp'
    };
    const flow = asString(user['flow']);
    if (flow.length > 0) {
      out.flow = flow;
    }
    if (tls !== undefined) {
      out.tls = tls;
    }
    if (transport !== undefined) {
      out.transport = transport;
    }
    return out;
  }

  if (protocol === 'vmess') {
    const server = firstObject(settings['vnext']);
    if (server === undefined) {
      return null;
    }
    const user = firstObject(server['users']);
    if (user === undefined) {
      return null;
    }
    const security = asString(user['security']);
    const out: SbOutbound = {
      type: 'vmess',
      tag: 'proxy',
      server: asString(server['address']),
      server_port: asNumber(server['port']),
      uuid: asString(user['id']),
      security: security.length > 0 ? security : 'auto',
      alter_id: asNumber(user['alterId'])
    };
    if (tls !== undefined) {
      out.tls = tls;
    }
    if (transport !== undefined) {
      out.transport = transport;
    }
    return out;
  }

  if (protocol === 'trojan') {
    const server = firstObject(settings['servers']);
    if (server === undefined) {
      return null;
    }
    const out: SbOutbound = {
      type: 'trojan',
      tag: 'proxy',
      server: asString(server['address']),
      server_port: asNumber(server['port']),
      password: asString(server['password'])
    };
    if (tls !== undefined) {
      out.tls = tls;
    }
    if (transport !== undefined) {
      out.transport = transport;
    }
    return out;
  }

  if (protocol === 'shadowsocks') {
    const server = firstObject(settings['servers']);
    if (server === undefined) {
      return null;
    }
    const out: SbOutbound = {
      type: 'shadowsocks',
      tag: 'proxy',
      server: asString(server['address']),
      server_port: asNumber(server['port']),
      method: asString(server['method']),
      password: asString(server['password'])
    };
    return out;
  }

  if (protocol === 'anytls') {
    const server = firstObject(settings['servers']);
    if (server === undefined) {
      return null;
    }
    const out: SbOutbound = {
      type: 'anytls',
      tag: 'proxy',
      server: asString(server['address']),
      server_port: asNumber(server['port']),
      password: asString(server['password']),
      tls: buildServerTls(server)
    };
    return out;
  }

  if (protocol === 'tuic') {
    const server = firstObject(settings['servers']);
    if (server === undefined) {
      return null;
    }
    const out: SbOutbound = {
      type: 'tuic',
      tag: 'proxy',
      server: asString(server['address']),
      server_port: asNumber(server['port']),
      uuid: asString(server['uuid']),
      password: asString(server['password']),
      tls: buildServerTls(server)
    };
    const congestionControl = asString(server['congestionControl']);
    if (congestionControl.length > 0) {
      out.congestion_control = congestionControl;
    }
    const udpRelayMode = asString(server['udpRelayMode']);
    if (udpRelayMode.length > 0) {
      out.udp_relay_mode = udpRelayMode;
    }
    return out;
  }

  if (protocol === 'hysteria2') {
    const server = firstObject(settings['servers']);
    if (server === undefined) {
      return null;
    }
    // Hysteria2 恒走 QUIC/TLS，且认证只用 password。TLS 字段(sni/alpn/insecure)内联在 server 上，
    // 复用 buildServerTls；缺省 alpn 走 h3。
    const tls = buildServerTls(server);
    if (tls.alpn === undefined || tls.alpn.length === 0) {
      tls.alpn = ['h3'];
    }
    const out: SbOutbound = {
      type: 'hysteria2',
      tag: 'proxy',
      server: asString(server['address']),
      server_port: asNumber(server['port']),
      password: asString(server['password']),
      tls
    };
    // salamander 混淆(可选)。
    const obfsPassword = asString(server['obfsPassword']);
    if (obfsPassword.length > 0) {
      out.obfs = { type: 'salamander', password: obfsPassword };
    }
    // 上下行带宽(可选)：Hey 存的是 "100 Mbps" 之类字符串，取前导数字作 Mbps。
    const upMbps = parseLeadingMbps(asString(server['bandwidthUp']));
    if (upMbps > 0) {
      out.up_mbps = upMbps;
    }
    const downMbps = parseLeadingMbps(asString(server['bandwidthDown']));
    if (downMbps > 0) {
      out.down_mbps = downMbps;
    }
    return out;
  }

  return null;
}

// 从 "100 Mbps" / "100mbps" / "100" 之类取前导整数(Mbps)。无法解析返回 0。
function parseLeadingMbps(value: string): number {
  const match = value.trim().match(/^\d+/);
  if (match === null) {
    return 0;
  }
  const parsed = parseInt(match[0], 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

// ---- 完整配置组装 ----

export function buildSingboxConfig(outboundJson: string, settings?: AppSettings, filesDir?: string): GeneratedSingboxConfig {
  let parsed: JsonObject | undefined;
  try {
    parsed = asObject(JSON.parse(outboundJson) as JsonField);
  } catch (error) {
    return { ok: false, message: 'sing-box: 节点 JSON 解析失败。', configJson: '' };
  }
  if (parsed === undefined) {
    return { ok: false, message: 'sing-box: 节点配置不是有效对象。', configJson: '' };
  }

  const protocol = asString(parsed['protocol']).toLowerCase();
  const proxy = convertOutbound(parsed);
  if (proxy === null) {
    return {
      ok: false,
      message: `sing-box 暂不支持该节点（协议: ${protocol.length > 0 ? protocol : '未知'}）。当前预览仅支持 VLESS / VMess / Trojan / Shadowsocks / AnyTLS / TUIC / Hysteria2。`,
      configJson: ''
    };
  }
  if (proxy.server === undefined || proxy.server.length === 0 || (proxy.server_port ?? 0) <= 0) {
    return { ok: false, message: 'sing-box: 节点缺少有效的地址或端口。', configJson: '' };
  }

  const remoteDns = normalizeSingboxProxyDns((settings?.remoteDns ?? '').trim());
  // 用户未填直连 DNS 时回落到系统 DNS，不预置任何具体服务商。
  const directDns = (settings?.domesticDns ?? '').trim().length > 0 ? (settings as AppSettings).domesticDns.trim() : 'local';
  const ipv6Enabled = settings?.ipv6Enabled === true;
  const logLevel = (settings?.logLevel ?? '').trim().length > 0 ? (settings as AppSettings).logLevel.trim() : 'warn';

  // tun2socks 数据面：sing-box 起一个本地 mixed(SOCKS+HTTP) 入站，监听与 Xray 相同的
  // VPN_DATA_SOCKS 端口，由 libheytun2socks.so 把 Harmony TUN fd 的流量转发进来。
  // 因此 sing-box 不需要 tun 入站 / OpenTun / gvisor tun 栈——甩掉了最难且最易出问题的一环。
  const socksIn: SbInbound = {
    type: 'mixed',
    tag: 'socks-in',
    listen: VPN_DATA_SOCKS_HOST,
    listen_port: VPN_DATA_SOCKS_PORT,
    sniff: true,
    sniff_override_destination: false
  };

  const directOut: SbOutbound = { type: 'direct', tag: 'direct' };
  const dnsOut: SbOutbound = { type: 'dns', tag: 'dns-out' };

  const dns: SbDns = {
    servers: [
      { tag: 'proxy-dns', address: remoteDns, detour: 'proxy' },
      { tag: 'direct-dns', address: directDns, detour: 'direct' }
    ],
    final: 'proxy-dns',
    strategy: ipv6Enabled ? 'prefer_ipv4' : 'ipv4_only'
  };

  // 关键：代理服务器地址是域名时，必须用 direct-dns 直连解析。否则默认(final: proxy-dns，
  // detour: proxy)会陷入死锁——连代理要先解析代理域名，而解析又要走还没连上的代理 →
  // 出站永远拨不通、全程无网络连接(Xray 侧靠 outbound 域名预解析写 hosts 处理了这层)。
  const serverHost = proxy.server ?? '';
  if (serverHost.length > 0 && !isIpLiteralHost(serverHost)) {
    dns.rules = [{ domain: [serverHost], server: 'direct-dns' }];
  }

  const route: SbRoute = {
    rules: [
      { protocol: 'dns', outbound: 'dns-out' },
      { ip_is_private: true, outbound: 'direct' }
    ],
    final: 'proxy',
    auto_detect_interface: false
  };

  const log: SbLog = { level: logLevel, timestamp: true };
  // 落盘 sing-box 分级日志(与 Xray 的 xray-core.log 对齐)，便于排查。
  if (filesDir !== undefined && filesDir.length > 0) {
    log.output = `${filesDir}/${SINGBOX_CORE_LOG_FILE}`;
  }

  const config: SbConfig = {
    log,
    dns,
    inbounds: [socksIn],
    outbounds: [proxy, directOut, dnsOut],
    route
  };

  return { ok: true, message: 'ok', configJson: JSON.stringify(config) };
}

// sing-box 经代理的「远程 DNS」规范化。
// 关键：明文 UDP DNS(裸 IP，如 "1.1.1.1")经 VLESS+gRPC 代理时依赖 UDP-over-代理(XUDP)，
// 实测在部分服务器不通 → 域名全部解析超时、连接不可用。DoH 走 TCP/443 经出站可靠得多
// (实测：明文 1.1.1.1 时目标站点打不开，同服务器改 DoH 后正常)。因此把裸 IP/主机升级为 DoH；
// 已带 scheme(https/tls/tcp/quic/h3…)的按用户意图保持不变。
function normalizeSingboxProxyDns(value: string): string {
  const v = value.trim();
  if (v.length === 0) {
    return 'https://1.1.1.1/dns-query';
  }
  if (/^[a-z0-9]+:\/\//i.test(v)) {
    return v;
  }
  return `https://${v}/dns-query`;
}

// 判断 host 是否为 IP 字面量(IPv4 或含冒号的 IPv6)——是则无需 DNS 解析。
function isIpLiteralHost(host: string): boolean {
  const trimmed = host.trim();
  if (trimmed.indexOf(':') >= 0) {
    return true;
  }
  return /^[0-9.]+$/.test(trimmed);
}
