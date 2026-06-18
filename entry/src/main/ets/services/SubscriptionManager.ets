import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { ProxyNode } from '../core/Profile';
import { decodeBase64ToUtf8 } from '../core/Encoding';
import {
  isSupportedShareLink,
  parseShareLinkToOutboundJson,
  ShareLinkParseResult
} from '../core/ShareLinkParser';
import { LOCAL_HTTP_PROXY_HOST, normalizeOutboundInput } from '../core/XrayConfig';

export interface SubscriptionUpdateResult {
  ok: boolean;
  message: string;
  nodes: Array<ProxyNode>;
  rawLength: number;
}

// 默认订阅 User-Agent。声明为 clash.meta 让支持格式协商的面板返回 Clash YAML，
// 与本文件的 Clash 解析器匹配；每条订阅可在编辑页覆盖，留空则回落到此值。
export const DEFAULT_SUBSCRIPTION_USER_AGENT: string = 'clash.meta Hey/0.1';

interface SubscriptionRequestHeader {
  'User-Agent': string;
  'Accept': string;
  'Accept-Encoding': string;
  'Content-Type': string;
}

interface JsonSubscriptionDocument {
  servers?: Array<Sip008Server>;
  outbound?: JsonSubscriptionOutbound;
  outbounds?: Array<JsonSubscriptionOutbound>;
}

interface Sip008Server {
  remarks?: string;
  name?: string;
  server?: string;
  server_port?: string | number;
  port?: string | number;
  method?: string;
  password?: string;
  plugin?: string;
  plugin_opts?: string;
}

interface ClashSection {
  indent: number;
  name: string;
}

interface ClashStreamSettings {
  network: string;
  security?: string;
  tcpSettings?: ClashTcpSettings;
  wsSettings?: ClashWsSettings;
  httpSettings?: ClashHttpSettings;
  grpcSettings?: ClashGrpcSettings;
  tlsSettings?: ClashTlsSettings;
  realitySettings?: ClashTlsSettings;
}

interface ClashTcpRequestHeaders {
  Host: Array<string>;
}

interface ClashTcpRequest {
  path: Array<string>;
  headers: ClashTcpRequestHeaders;
}

interface ClashTcpHeader {
  type: string;
  request?: ClashTcpRequest;
}

interface ClashTcpSettings {
  header: ClashTcpHeader;
}

interface ClashWsHeaders {
  Host: string;
}

interface ClashWsSettings {
  path: string;
  headers: ClashWsHeaders;
}

interface ClashHttpSettings {
  host: Array<string>;
  path: string;
}

interface ClashGrpcSettings {
  serviceName: string;
  multiMode: boolean;
  idle_timeout: number;
  health_check_timeout: number;
}

interface ClashTlsSettings {
  allowInsecure?: boolean;
  serverName?: string;
  fingerprint?: string;
  alpn?: Array<string>;
  publicKey?: string;
  shortId?: string;
  spiderX?: string;
  mldsa65Verify?: string;
  show?: boolean;
}

interface ClashOutbound {
  protocol: string;
  tag: string;
  settings: ClashOutboundSettings;
  streamSettings?: ClashStreamSettings;
}

type ClashOutboundSettings = ClashVlessSettings | ClashVmessSettings | ClashTrojanSettings | ClashShadowsocksSettings | ClashGenericSettings | ClashHysteria2Settings;

interface JsonSubscriptionOutbound {
  protocol?: string;
  tag?: string;
  settings?: ClashOutboundSettings;
  streamSettings?: ClashStreamSettings;
}

interface ClashVlessUser {
  id: string;
  encryption: string;
  flow?: string;
}

interface ClashVlessServer {
  address: string;
  port: number;
  users: Array<ClashVlessUser>;
}

interface ClashVlessSettings {
  vnext: Array<ClashVlessServer>;
}

interface ClashVmessUser {
  id: string;
  alterId: number;
  security: string;
}

interface ClashVmessServer {
  address: string;
  port: number;
  users: Array<ClashVmessUser>;
}

interface ClashVmessSettings {
  vnext: Array<ClashVmessServer>;
}

interface ClashTrojanServer {
  address: string;
  port: number;
  password: string;
}

interface ClashTrojanSettings {
  servers: Array<ClashTrojanServer>;
}

interface ClashShadowsocksServer {
  address: string;
  port: number;
  method: string;
  password: string;
}

interface ClashShadowsocksSettings {
  servers: Array<ClashShadowsocksServer>;
}

interface ClashGenericUser {
  user: string;
  pass: string;
}

interface ClashGenericServer {
  address: string;
  port: number;
  users?: Array<ClashGenericUser>;
}

interface ClashGenericSettings {
  servers: Array<ClashGenericServer>;
}

interface ClashHysteria2Server {
  address: string;
  port: number;
  password: string;
  sni?: string;
  obfsPassword?: string;
  insecure?: boolean;
}

interface ClashHysteria2Settings {
  servers: Array<ClashHysteria2Server>;
}

export class SubscriptionManager {
  static async fetchAndParse(url: string, userAgent: string = '', allowInsecureUrl: boolean = false, proxyPort: number = 0): Promise<SubscriptionUpdateResult> {
    const trimmedUrl = url.trim();
    const validationMessage = SubscriptionManager.validateSubscriptionUrl(trimmedUrl, allowInsecureUrl);
    if (validationMessage.length > 0) {
      const result: SubscriptionUpdateResult = {
        ok: false,
        message: validationMessage,
        nodes: [],
        rawLength: 0
      };
      return result;
    }

    const content = await SubscriptionManager.fetchTextWithFallback(trimmedUrl, userAgent, allowInsecureUrl, proxyPort);
    const nodes = SubscriptionManager.parseSubscriptionContent(content, trimmedUrl);
    const result: SubscriptionUpdateResult = {
      ok: nodes.length > 0,
      message: nodes.length > 0 ? `订阅更新完成，共 ${nodes.length} 个可用节点。` : '订阅内容里没有识别到支持的节点。',
      nodes,
      rawLength: content.length
    };
    return result;
  }

  static shouldUseSubscriptionProxy(proxyPort: number): boolean {
    return proxyPort > 0 && Math.floor(proxyPort) === proxyPort && proxyPort <= 65535;
  }

  static validateSubscriptionUrl(url: string, allowInsecureUrl: boolean): string {
    const trimmedUrl = url.trim();
    if (!SubscriptionManager.isHttpUrl(trimmedUrl)) {
      return '订阅链接必须是 http:// 或 https://。';
    }
    if (!allowInsecureUrl && SubscriptionManager.isInsecureHttpUrl(trimmedUrl)) {
      return 'HTTP 订阅链接不安全，请开启允许不安全订阅链接后重试。';
    }
    return '';
  }

  static parseSubscriptionContent(content: string, sourceUrl: string): Array<ProxyNode> {
    const raw = SubscriptionManager.normalizeSubscriptionPayload(content);
    const rawNodes = SubscriptionManager.parseText(raw, sourceUrl);
    if (rawNodes.length > 0) {
      return rawNodes;
    }

    try {
      const decoded = decodeBase64ToUtf8(raw);
      return SubscriptionManager.parseText(SubscriptionManager.normalizeSubscriptionPayload(decoded), sourceUrl);
    } catch (error) {
      return [];
    }
  }

  private static async fetchTextWithFallback(url: string, userAgent: string, allowInsecureUrl: boolean, proxyPort: number): Promise<string> {
    if (!SubscriptionManager.shouldUseSubscriptionProxy(proxyPort)) {
      return SubscriptionManager.fetchText(url, 0, userAgent, allowInsecureUrl, 0);
    }
    try {
      return await SubscriptionManager.fetchText(url, 0, userAgent, allowInsecureUrl, proxyPort);
    } catch (error) {
      return SubscriptionManager.fetchText(url, 0, userAgent, allowInsecureUrl, 0);
    }
  }

  private static async fetchText(url: string, redirectCount: number, userAgent: string, allowInsecureUrl: boolean, proxyPort: number): Promise<string> {
    if (redirectCount > 5) {
      throw new Error('HTTP redirect limit reached');
    }

    const resolvedUserAgent = userAgent.trim().length > 0 ? userAgent.trim() : DEFAULT_SUBSCRIPTION_USER_AGENT;
    const request = http.createHttp();
    try {
      const header: SubscriptionRequestHeader = {
        'User-Agent': resolvedUserAgent,
        'Accept': 'text/plain, application/octet-stream, application/json, application/yaml, text/yaml, */*',
        'Accept-Encoding': 'identity',
        'Content-Type': 'text/plain; charset=utf-8'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 30000,
        connectTimeout: 15000,
        usingCache: false,
        header
      };
      if (SubscriptionManager.shouldUseSubscriptionProxy(proxyPort)) {
        const proxy: http.HttpProxy = {
          host: LOCAL_HTTP_PROXY_HOST,
          port: proxyPort,
          exclusionList: []
        };
        options.usingProxy = proxy;
      }
      const response = await request.request(url, options);
      const responseCode = Number(response.responseCode);
      if (SubscriptionManager.isRedirectCode(responseCode)) {
        const redirectUrl = SubscriptionManager.redirectUrl(url, JSON.stringify(response.header));
        if (redirectUrl.length > 0) {
          const validationMessage = SubscriptionManager.validateSubscriptionUrl(redirectUrl, allowInsecureUrl);
          if (validationMessage.length > 0) {
            throw new Error(validationMessage);
          }
          return SubscriptionManager.fetchText(redirectUrl, redirectCount + 1, userAgent, allowInsecureUrl, proxyPort);
        }
      }
      if (responseCode < 200 || responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      if (typeof response.result === 'string') {
        return response.result;
      }
      if (response.result instanceof ArrayBuffer) {
        const decoder = util.TextDecoder.create('utf-8');
        return decoder.decode(new Uint8Array(response.result));
      }
      const objectText = JSON.stringify(response.result);
      return objectText === undefined ? '' : objectText;
    } finally {
      request.destroy();
    }
  }

  private static parseLines(content: string, sourceUrl: string): Array<ProxyNode> {
    const normalized = content.split('\r\n').join('\n').split('\r').join('\n');
    const lines = normalized.split('\n');
    const seen = new Set<string>();
    const nodes: Array<ProxyNode> = [];
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (line.length === 0 || seen.has(line) || !isSupportedShareLink(line)) {
        continue;
      }
      seen.add(line);
      const parsed = SubscriptionManager.parseNode(line, sourceUrl, index);
      if (parsed !== null) {
        nodes.push(parsed);
      }
    }
    return nodes;
  }

  private static parseText(content: string, sourceUrl: string): Array<ProxyNode> {
    const linkNodes = SubscriptionManager.parseLines(content, sourceUrl);
    if (linkNodes.length > 0) {
      return linkNodes;
    }

    const clashNodes = SubscriptionManager.parseClashYaml(content, sourceUrl);
    if (clashNodes.length > 0) {
      return clashNodes;
    }

    return SubscriptionManager.parseJsonSubscription(content, sourceUrl);
  }

  private static normalizeSubscriptionPayload(content: string): string {
    let value = content.trim();
    if (value.startsWith('\uFEFF')) {
      value = value.substring(1).trim();
    }
    const lower = value.toLowerCase();
    const dataPrefix = 'data:text/plain;base64,';
    if (lower.startsWith(dataPrefix)) {
      return value.substring(dataPrefix.length).trim();
    }
    const dataBase64Marker = ';base64,';
    const dataBase64Index = lower.indexOf(dataBase64Marker);
    if (lower.startsWith('data:') && dataBase64Index > 0) {
      return value.substring(dataBase64Index + dataBase64Marker.length).trim();
    }
    return value;
  }

  private static parseNode(line: string, sourceUrl: string, index: number): ProxyNode | null {
    const imported: ShareLinkParseResult = parseShareLinkToOutboundJson(line);
    if (!imported.success) {
      return null;
    }

    const validation = normalizeOutboundInput(line);
    if (!validation.valid) {
      return null;
    }

    const now = Date.now();
    const node: ProxyNode = {
      id: SubscriptionManager.makeNodeId(sourceUrl, line),
      name: SubscriptionManager.makeNodeName(imported, validation.normalizedJson, index),
      protocol: validation.protocol,
      outboundJson: validation.normalizedJson,
      configType: validation.configType,
      sourceUrl,
      rawLink: line,
      updatedAt: now,
      delayMs: -1,
      delayTestAt: 0,
      delayStatus: ''
    };
    return node;
  }

  private static makeNodeFromOutboundJson(outboundJson: string, sourceUrl: string, rawLink: string, name: string, index: number): ProxyNode | null {
    const validation = normalizeOutboundInput(outboundJson);
    if (!validation.valid) {
      return null;
    }

    const now = Date.now();
    const node: ProxyNode = {
      id: SubscriptionManager.makeNodeId(sourceUrl, rawLink.length > 0 ? rawLink : validation.normalizedJson),
      name: name.length > 0 ? name : SubscriptionManager.makeNodeNameFromJson(validation.protocol, validation.normalizedJson, index),
      protocol: validation.protocol,
      outboundJson: validation.normalizedJson,
      configType: validation.configType,
      sourceUrl,
      rawLink,
      updatedAt: now,
      delayMs: -1,
      delayTestAt: 0,
      delayStatus: ''
    };
    return node;
  }

  private static makeNodeNameFromJson(protocol: string, outboundJson: string, index: number): string {
    const server = SubscriptionManager.describeServer(outboundJson);
    if (server.length > 0) {
      return `${protocol.toUpperCase()} ${server}`;
    }
    return `${protocol.toUpperCase()} #${index + 1}`;
  }

  private static parseJsonSubscription(content: string, sourceUrl: string): Array<ProxyNode> {
    const trimmed = content.trim();
    if (trimmed.length === 0) {
      return [];
    }

    try {
      if (trimmed.startsWith('[')) {
        return SubscriptionManager.parseJsonOutbounds(JSON.parse(trimmed) as Array<JsonSubscriptionOutbound>, sourceUrl);
      }

      const document = JSON.parse(trimmed) as JsonSubscriptionDocument;
      const outboundNodes = SubscriptionManager.parseJsonDocumentOutbounds(document, sourceUrl);
      if (outboundNodes.length > 0) {
        return outboundNodes;
      }
      return SubscriptionManager.parseSip008Document(document, sourceUrl);
    } catch (error) {
      return [];
    }
  }

  private static parseJsonDocumentOutbounds(document: JsonSubscriptionDocument, sourceUrl: string): Array<ProxyNode> {
    if (document.outbounds !== undefined) {
      return SubscriptionManager.parseJsonOutbounds(document.outbounds, sourceUrl);
    }
    if (document.outbound !== undefined) {
      const outbounds = new Array<JsonSubscriptionOutbound>();
      outbounds.push(document.outbound);
      return SubscriptionManager.parseJsonOutbounds(outbounds, sourceUrl);
    }
    return [];
  }

  private static parseJsonOutbounds(outbounds: Array<JsonSubscriptionOutbound>, sourceUrl: string): Array<ProxyNode> {
    const nodes = new Array<ProxyNode>();
    for (let index = 0; index < outbounds.length; index++) {
      const outbound = outbounds[index];
      if (outbound.protocol === undefined || outbound.settings === undefined) {
        continue;
      }
      const node = SubscriptionManager.makeNodeFromOutboundJson(
        JSON.stringify(outbound, null, 2),
        sourceUrl,
        '',
        outbound.tag === undefined ? '' : outbound.tag,
        index
      );
      if (node !== null) {
        nodes.push(node);
      }
    }
    return nodes;
  }

  private static parseSip008Document(document: JsonSubscriptionDocument, sourceUrl: string): Array<ProxyNode> {
    const nodes = new Array<ProxyNode>();
    const servers = document.servers ?? [];
    for (let index = 0; index < servers.length; index++) {
      const server = servers[index];
      const host = SubscriptionManager.valueOr(server.server, '');
      const port = SubscriptionManager.parsePortValue(server.server_port ?? server.port);
      const method = SubscriptionManager.valueOr(server.method, '').toLowerCase();
      const password = SubscriptionManager.valueOr(server.password, '');
      if (host.length === 0 || port <= 0 || method.length === 0 || password.length === 0) {
        continue;
      }

      const shadowsocksServer: ClashShadowsocksServer = {
        address: host,
        port,
        method,
        password
      };
      const settings: ClashShadowsocksSettings = {
        servers: [shadowsocksServer]
      };
      const outbound: ClashOutbound = {
        protocol: 'shadowsocks',
        tag: 'proxy',
        settings
      };
      const node = SubscriptionManager.makeNodeFromOutboundJson(JSON.stringify(outbound, null, 2), sourceUrl, '', SubscriptionManager.valueOr(server.remarks, SubscriptionManager.valueOr(server.name, '')), index);
      if (node !== null) {
        nodes.push(node);
      }
    }
    return nodes;
  }

  private static parseClashYaml(content: string, sourceUrl: string): Array<ProxyNode> {
    const entries = SubscriptionManager.extractClashProxyEntries(content);
    const nodes = new Array<ProxyNode>();
    for (let index = 0; index < entries.length; index++) {
      const entry = entries[index];
      const outbound = SubscriptionManager.clashEntryToOutbound(entry);
      if (outbound === null) {
        continue;
      }
      const node = SubscriptionManager.makeNodeFromOutboundJson(
        JSON.stringify(outbound, null, 2),
        sourceUrl,
        '',
        SubscriptionManager.mapValue(entry, 'name', ''),
        index
      );
      if (node !== null) {
        nodes.push(node);
      }
    }
    return nodes;
  }

  private static extractClashProxyEntries(content: string): Array<Map<string, string>> {
    const normalized = content.split('\r\n').join('\n').split('\r').join('\n');
    const lines = normalized.split('\n');
    const entries = new Array<Map<string, string>>();
    let inProxies = false;
    let proxiesIndent = -1;
    let current: Map<string, string> | null = null;
    let sections = new Array<ClashSection>();

    for (let index = 0; index < lines.length; index++) {
      const rawLine = lines[index];
      const trimmed = rawLine.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }

      const indent = SubscriptionManager.countIndent(rawLine);
      if (!inProxies) {
        if (trimmed === 'proxies:') {
          inProxies = true;
          proxiesIndent = indent;
        }
        continue;
      }

      if (indent <= proxiesIndent && !trimmed.startsWith('- ')) {
        SubscriptionManager.pushClashEntry(entries, current);
        current = null;
        sections = new Array<ClashSection>();
        break;
      }

      if (trimmed.startsWith('- ')) {
        SubscriptionManager.pushClashEntry(entries, current);
        current = new Map<string, string>();
        sections = new Array<ClashSection>();
        const body = trimmed.substring(2).trim();
        if (body.startsWith('{') && body.endsWith('}')) {
          SubscriptionManager.parseInlineMap(body, current, '');
        } else {
          SubscriptionManager.parseYamlPair(body, current, '');
        }
        continue;
      }

      if (current === null) {
        continue;
      }

      while (sections.length > 0 && indent <= sections[sections.length - 1].indent) {
        sections.pop();
      }

      if (trimmed.endsWith(':') && trimmed.indexOf(':') === trimmed.length - 1) {
        const section: ClashSection = {
          indent,
          name: SubscriptionManager.normalizeYamlKey(trimmed.substring(0, trimmed.length - 1))
        };
        sections.push(section);
        continue;
      }

      SubscriptionManager.parseYamlPair(trimmed, current, SubscriptionManager.sectionPrefix(sections));
    }

    SubscriptionManager.pushClashEntry(entries, current);
    return entries;
  }

  private static pushClashEntry(entries: Array<Map<string, string>>, entry: Map<string, string> | null): void {
    if (entry !== null && SubscriptionManager.mapValue(entry, 'type', '').length > 0) {
      entries.push(entry);
    }
  }

  private static parseYamlPair(line: string, target: Map<string, string>, prefix: string): void {
    const colonIndex = SubscriptionManager.findTopLevelColon(line);
    if (colonIndex <= 0) {
      return;
    }
    const key = SubscriptionManager.normalizeYamlKey(line.substring(0, colonIndex));
    const rawValue = SubscriptionManager.stripYamlValue(line.substring(colonIndex + 1));
    if (rawValue.startsWith('{') && rawValue.endsWith('}')) {
      SubscriptionManager.parseInlineMap(rawValue, target, SubscriptionManager.joinKey(prefix, key));
      return;
    }
    target.set(SubscriptionManager.joinKey(prefix, key), rawValue);
  }

  private static parseInlineMap(value: string, target: Map<string, string>, prefix: string): void {
    const body = value.substring(1, value.length - 1);
    const pairs = SubscriptionManager.splitInlineMapPairs(body);
    for (let index = 0; index < pairs.length; index++) {
      const pair = pairs[index];
      const colonIndex = SubscriptionManager.findTopLevelColon(pair);
      if (colonIndex <= 0) {
        continue;
      }
      const key = SubscriptionManager.normalizeYamlKey(pair.substring(0, colonIndex));
      const rawValue = SubscriptionManager.stripYamlValue(pair.substring(colonIndex + 1));
      if (rawValue.startsWith('{') && rawValue.endsWith('}')) {
        SubscriptionManager.parseInlineMap(rawValue, target, SubscriptionManager.joinKey(prefix, key));
      } else {
        target.set(SubscriptionManager.joinKey(prefix, key), rawValue);
      }
    }
  }

  private static splitInlineMapPairs(value: string): Array<string> {
    const pairs = new Array<string>();
    let depth = 0;
    let quote = '';
    let start = 0;
    for (let index = 0; index < value.length; index++) {
      const ch = value.charAt(index);
      if (quote.length > 0) {
        if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '{' || ch === '[') {
        depth++;
      } else if (ch === '}' || ch === ']') {
        depth--;
      } else if (ch === ',' && depth === 0) {
        pairs.push(value.substring(start, index).trim());
        start = index + 1;
      }
    }
    pairs.push(value.substring(start).trim());
    return pairs;
  }

  private static clashEntryToOutbound(entry: Map<string, string>): ClashOutbound | null {
    const type = SubscriptionManager.mapValue(entry, 'type', '').toLowerCase();
    const host = SubscriptionManager.mapValue(entry, 'server', '');
    const port = SubscriptionManager.parsePortString(SubscriptionManager.mapValue(entry, 'port', ''));
    if (host.length === 0 || port <= 0) {
      return null;
    }

    if (type === 'vless') {
      const id = SubscriptionManager.mapFirstValue(entry, ['uuid', 'id'], '');
      if (id.length === 0) {
        return null;
      }
      const user: ClashVlessUser = {
        id,
        encryption: SubscriptionManager.mapValue(entry, 'encryption', 'none')
      };
      const flow = SubscriptionManager.mapValue(entry, 'flow', '');
      if (flow.length > 0) {
        user.flow = flow;
      }
      const server: ClashVlessServer = {
        address: host,
        port,
        users: [user]
      };
      const settings: ClashVlessSettings = {
        vnext: [server]
      };
      const outbound: ClashOutbound = {
        protocol: 'vless',
        tag: 'proxy',
        settings,
        streamSettings: SubscriptionManager.buildClashStreamSettings(entry)
      };
      return outbound;
    }

    if (type === 'vmess') {
      const id = SubscriptionManager.mapFirstValue(entry, ['uuid', 'id'], '');
      if (id.length === 0) {
        return null;
      }
      const user: ClashVmessUser = {
        id,
        alterId: SubscriptionManager.parseIntegerString(SubscriptionManager.mapFirstValue(entry, ['alterid', 'alter-id', 'aid'], '0'), 0),
        security: SubscriptionManager.mapFirstValue(entry, ['cipher', 'security'], 'auto')
      };
      const server: ClashVmessServer = {
        address: host,
        port,
        users: [user]
      };
      const settings: ClashVmessSettings = {
        vnext: [server]
      };
      const outbound: ClashOutbound = {
        protocol: 'vmess',
        tag: 'proxy',
        settings,
        streamSettings: SubscriptionManager.buildClashStreamSettings(entry)
      };
      return outbound;
    }

    if (type === 'trojan') {
      const password = SubscriptionManager.mapValue(entry, 'password', '');
      if (password.length === 0) {
        return null;
      }
      const server: ClashTrojanServer = {
        address: host,
        port,
        password
      };
      const settings: ClashTrojanSettings = {
        servers: [server]
      };
      const outbound: ClashOutbound = {
        protocol: 'trojan',
        tag: 'proxy',
        settings,
        streamSettings: SubscriptionManager.buildClashStreamSettings(entry, 'tls')
      };
      return outbound;
    }

    if (type === 'ss' || type === 'shadowsocks') {
      const method = SubscriptionManager.mapFirstValue(entry, ['cipher', 'method'], '').toLowerCase();
      const password = SubscriptionManager.mapValue(entry, 'password', '');
      if (method.length === 0 || password.length === 0) {
        return null;
      }
      const server: ClashShadowsocksServer = {
        address: host,
        port,
        method,
        password
      };
      const settings: ClashShadowsocksSettings = {
        servers: [server]
      };
      const outbound: ClashOutbound = {
        protocol: 'shadowsocks',
        tag: 'proxy',
        settings,
        streamSettings: SubscriptionManager.buildClashPluginStreamSettings(entry)
      };
      return outbound;
    }

    if (type === 'socks5' || type === 'socks') {
      const server: ClashGenericServer = {
        address: host,
        port
      };
      const user = SubscriptionManager.buildGenericUser(entry);
      if (user !== null) {
        server.users = [user];
      }
      const settings: ClashGenericSettings = {
        servers: [server]
      };
      const outbound: ClashOutbound = {
        protocol: 'socks',
        tag: 'proxy',
        settings
      };
      return outbound;
    }

    if (type === 'http' || type === 'https') {
      const server: ClashGenericServer = {
        address: host,
        port
      };
      const user = SubscriptionManager.buildGenericUser(entry);
      if (user !== null) {
        server.users = [user];
      }
      const settings: ClashGenericSettings = {
        servers: [server]
      };
      const outbound: ClashOutbound = {
        protocol: 'http',
        tag: 'proxy',
        settings
      };
      return outbound;
    }

    if (type === 'hysteria2' || type === 'hy2') {
      const password = SubscriptionManager.mapFirstValue(entry, ['password', 'auth'], '');
      if (password.length === 0) {
        return null;
      }
      const server: ClashHysteria2Server = {
        address: host,
        port,
        password
      };
      const sni = SubscriptionManager.mapFirstValue(entry, ['sni', 'servername'], '');
      if (sni.length > 0) {
        server.sni = sni;
      }
      const obfsPassword = SubscriptionManager.mapFirstValue(entry, ['obfs-password', 'obfs.password'], '');
      if (obfsPassword.length > 0) {
        server.obfsPassword = obfsPassword;
      }
      if (SubscriptionManager.mapValue(entry, 'skip-cert-verify', '').length > 0) {
        server.insecure = SubscriptionManager.mapBoolean(entry, 'skip-cert-verify', false);
      }
      const settings: ClashHysteria2Settings = {
        servers: [server]
      };
      const outbound: ClashOutbound = {
        protocol: 'hysteria2',
        tag: 'proxy',
        settings
      };
      return outbound;
    }

    return null;
  }

  private static buildGenericUser(entry: Map<string, string>): ClashGenericUser | null {
    const user = SubscriptionManager.mapFirstValue(entry, ['username', 'user'], '');
    const pass = SubscriptionManager.mapFirstValue(entry, ['password', 'pass'], '');
    if (user.length === 0 && pass.length === 0) {
      return null;
    }
    const genericUser: ClashGenericUser = {
      user,
      pass
    };
    return genericUser;
  }

  private static buildClashPluginStreamSettings(entry: Map<string, string>): ClashStreamSettings | undefined {
    const plugin = SubscriptionManager.mapValue(entry, 'plugin', '').toLowerCase();
    if (plugin !== 'obfs') {
      return undefined;
    }
    const mode = SubscriptionManager.mapFirstValue(entry, ['plugin-opts.mode', 'plugin_opts.mode'], '');
    if (mode !== 'http') {
      return undefined;
    }
    const host = SubscriptionManager.mapFirstValue(entry, ['plugin-opts.host', 'plugin_opts.host'], '');
    const path = SubscriptionManager.mapFirstValue(entry, ['plugin-opts.path', 'plugin_opts.path'], '');
    const headers: ClashTcpRequestHeaders = {
      Host: SubscriptionManager.splitCsv(host)
    };
    const request: ClashTcpRequest = {
      path: SubscriptionManager.splitCsvWithDefault(path, '/'),
      headers
    };
    const header: ClashTcpHeader = {
      type: 'http',
      request
    };
    const tcpSettings: ClashTcpSettings = {
      header
    };
    const stream: ClashStreamSettings = {
      network: 'tcp',
      tcpSettings
    };
    return stream;
  }

  private static buildClashStreamSettings(entry: Map<string, string>, defaultSecurity: string = ''): ClashStreamSettings {
    let network = SubscriptionManager.mapFirstValue(entry, ['network', 'net'], 'tcp').toLowerCase();
    if (network === 'h2' || network === 'http') {
      network = 'h2';
    } else if (network !== 'ws' && network !== 'grpc') {
      network = 'tcp';
    }

    const stream: ClashStreamSettings = {
      network
    };
    if (network === 'ws') {
      const path = SubscriptionManager.mapFirstValue(entry, ['ws-opts.path', 'ws_opts.path', 'path'], '/');
      const host = SubscriptionManager.mapFirstValue(entry, ['ws-opts.headers.host', 'ws-opts.headers.Host', 'ws_opts.headers.host', 'host'], '');
      const headers: ClashWsHeaders = {
        Host: host
      };
      const wsSettings: ClashWsSettings = {
        path: path.length > 0 ? path : '/',
        headers
      };
      stream.wsSettings = wsSettings;
    } else if (network === 'grpc') {
      const grpcSettings: ClashGrpcSettings = {
        serviceName: SubscriptionManager.mapFirstValue(entry, ['grpc-opts.grpc-service-name', 'grpc_opts.grpc-service-name', 'serviceName'], ''),
        multiMode: SubscriptionManager.mapFirstValue(entry, ['grpc-opts.grpc-mode', 'mode'], '') === 'multi',
        idle_timeout: 60,
        health_check_timeout: 20
      };
      stream.grpcSettings = grpcSettings;
    } else if (network === 'h2') {
      const httpSettings: ClashHttpSettings = {
        host: SubscriptionManager.splitCsv(SubscriptionManager.mapFirstValue(entry, ['h2-opts.host', 'http-opts.host', 'host'], '')),
        path: SubscriptionManager.mapFirstValue(entry, ['h2-opts.path', 'http-opts.path', 'path'], '/')
      };
      stream.httpSettings = httpSettings;
    } else {
      const header: ClashTcpHeader = {
        type: 'none'
      };
      const tcpSettings: ClashTcpSettings = {
        header
      };
      stream.tcpSettings = tcpSettings;
    }

    SubscriptionManager.applyClashSecurity(entry, stream, defaultSecurity);
    return stream;
  }

  private static applyClashSecurity(entry: Map<string, string>, stream: ClashStreamSettings, defaultSecurity: string): void {
    const publicKey = SubscriptionManager.mapFirstValue(entry, ['reality-opts.public-key', 'reality_opts.public-key', 'reality-opts.publicKey', 'pbk'], '');
    let security = defaultSecurity;
    if (publicKey.length > 0) {
      security = 'reality';
    } else if (SubscriptionManager.mapBoolean(entry, 'tls', false)) {
      security = 'tls';
    }

    if (security !== 'tls' && security !== 'reality') {
      return;
    }

    const tlsSettings: ClashTlsSettings = {
      allowInsecure: SubscriptionManager.mapBoolean(entry, 'skip-cert-verify', false)
    };
    const sni = SubscriptionManager.mapFirstValue(entry, ['sni', 'servername', 'serverName'], SubscriptionManager.deriveClashServerName(entry));
    if (sni.length > 0) {
      tlsSettings.serverName = sni;
    }
    const fingerprint = SubscriptionManager.mapFirstValue(entry, ['client-fingerprint', 'fingerprint', 'fp'], '');
    if (fingerprint.length > 0) {
      tlsSettings.fingerprint = fingerprint;
    }
    const alpn = SubscriptionManager.splitCsv(SubscriptionManager.mapValue(entry, 'alpn', ''));
    if (alpn.length > 0) {
      tlsSettings.alpn = alpn;
    }
    if (publicKey.length > 0) {
      tlsSettings.publicKey = publicKey;
      tlsSettings.shortId = SubscriptionManager.mapFirstValue(entry, ['reality-opts.short-id', 'reality_opts.short-id', 'sid'], '');
      const spiderX = SubscriptionManager.mapFirstValue(entry, ['reality-opts.spider-x', 'reality_opts.spider-x', 'reality-opts.spiderX', 'spx'], '');
      if (spiderX.length > 0) {
        tlsSettings.spiderX = spiderX;
      }
      const mldsa65Verify = SubscriptionManager.mapFirstValue(entry, ['reality-opts.mldsa65-verify', 'reality_opts.mldsa65-verify', 'reality-opts.mldsa65Verify', 'mldsa65Verify', 'pqv'], '');
      if (mldsa65Verify.length > 0) {
        tlsSettings.mldsa65Verify = mldsa65Verify;
      }
      tlsSettings.show = false;
    }

    stream.security = security;
    if (security === 'tls') {
      stream.tlsSettings = tlsSettings;
    } else {
      stream.realitySettings = tlsSettings;
    }
  }

  private static valueOr(value: string | undefined, fallback: string): string {
    return value === undefined ? fallback : value;
  }

  private static deriveClashServerName(entry: Map<string, string>): string {
    const network = SubscriptionManager.mapFirstValue(entry, ['network', 'net'], 'tcp').toLowerCase();
    if (network === 'ws') {
      return SubscriptionManager.firstCsvValue(SubscriptionManager.mapFirstValue(entry, ['ws-opts.headers.host', 'ws_opts.headers.host', 'host'], ''));
    }
    if (network === 'h2' || network === 'http') {
      return SubscriptionManager.firstCsvValue(SubscriptionManager.mapFirstValue(entry, ['h2-opts.host', 'http-opts.host', 'host'], ''));
    }
    if (network === 'grpc') {
      return SubscriptionManager.mapFirstValue(entry, ['grpc-opts.authority', 'grpc_opts.authority'], '');
    }
    return '';
  }

  private static parsePortValue(value: string | number | undefined): number {
    if (value === undefined) {
      return -1;
    }
    return SubscriptionManager.parsePortString(value.toString());
  }

  private static parsePortString(value: string): number {
    const port = Number(value.trim());
    if (value.trim().length === 0 || port < 1 || port > 65535 || Math.floor(port) !== port) {
      return -1;
    }
    return port;
  }

  private static parseIntegerString(value: string, fallback: number): number {
    const number = Number(value.trim());
    if (value.trim().length === 0 || Number.isNaN(number) || Math.floor(number) !== number) {
      return fallback;
    }
    return number;
  }

  private static mapValue(entry: Map<string, string>, key: string, fallback: string): string {
    const value = entry.get(SubscriptionManager.normalizeYamlKey(key));
    return value === undefined ? fallback : value;
  }

  private static mapFirstValue(entry: Map<string, string>, keys: Array<string>, fallback: string): string {
    for (let index = 0; index < keys.length; index++) {
      const value = SubscriptionManager.mapValue(entry, keys[index], '');
      if (value.length > 0) {
        return value;
      }
    }
    return fallback;
  }

  private static mapBoolean(entry: Map<string, string>, key: string, fallback: boolean): boolean {
    const raw = SubscriptionManager.mapValue(entry, key, '');
    if (raw.length === 0) {
      return fallback;
    }
    const lower = raw.toLowerCase();
    return lower === 'true' || lower === '1' || lower === 'yes';
  }

  private static countIndent(value: string): number {
    let indent = 0;
    while (indent < value.length && value.charAt(indent) === ' ') {
      indent++;
    }
    return indent;
  }

  private static sectionPrefix(sections: Array<ClashSection>): string {
    let prefix = '';
    for (let index = 0; index < sections.length; index++) {
      prefix = SubscriptionManager.joinKey(prefix, sections[index].name);
    }
    return prefix;
  }

  private static joinKey(prefix: string, key: string): string {
    const normalizedKey = SubscriptionManager.normalizeYamlKey(key);
    if (prefix.length === 0) {
      return normalizedKey;
    }
    if (normalizedKey.length === 0) {
      return prefix;
    }
    return `${prefix}.${normalizedKey}`;
  }

  private static normalizeYamlKey(key: string): string {
    return SubscriptionManager.stripYamlValue(key).toLowerCase().split('_').join('-');
  }

  private static findTopLevelColon(value: string): number {
    let quote = '';
    let depth = 0;
    for (let index = 0; index < value.length; index++) {
      const ch = value.charAt(index);
      if (quote.length > 0) {
        if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '{' || ch === '[') {
        depth++;
      } else if (ch === '}' || ch === ']') {
        depth--;
      } else if (ch === ':' && depth === 0) {
        return index;
      }
    }
    return -1;
  }

  private static stripYamlValue(value: string): string {
    let result = '';
    let quote = '';
    for (let index = 0; index < value.length; index++) {
      const ch = value.charAt(index);
      if (quote.length > 0) {
        if (ch === quote) {
          quote = '';
        }
        result += ch;
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        result += ch;
      } else if (ch === '#') {
        break;
      } else {
        result += ch;
      }
    }

    result = result.trim();
    if (result.length >= 2) {
      const first = result.charAt(0);
      const last = result.charAt(result.length - 1);
      if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
        result = result.substring(1, result.length - 1);
      }
    }
    return result;
  }

  private static splitCsv(value: string): Array<string> {
    const result = new Array<string>();
    if (value.length === 0) {
      return result;
    }
    const normalized = value.replace('[', '').replace(']', '');
    const parts = normalized.split(',');
    for (let index = 0; index < parts.length; index++) {
      const part = SubscriptionManager.stripYamlValue(parts[index]);
      if (part.length > 0) {
        result.push(part);
      }
    }
    return result;
  }

  private static splitCsvWithDefault(value: string, fallback: string): Array<string> {
    const values = SubscriptionManager.splitCsv(value);
    if (values.length > 0) {
      return values;
    }
    return [fallback];
  }

  private static firstCsvValue(value: string): string {
    const values = SubscriptionManager.splitCsv(value);
    return values.length > 0 ? values[0] : '';
  }

  private static isRedirectCode(code: number): boolean {
    return code === 301 || code === 302 || code === 303 || code === 307 || code === 308;
  }

  private static redirectUrl(currentUrl: string, headerJson: string): string {
    const location = SubscriptionManager.findJsonString(headerJson, 'Location');
    if (location.length > 0) {
      return SubscriptionManager.resolveUrl(currentUrl, location);
    }
    const lowerLocation = SubscriptionManager.findJsonString(headerJson, 'location');
    if (lowerLocation.length > 0) {
      return SubscriptionManager.resolveUrl(currentUrl, lowerLocation);
    }
    const firstLocation = SubscriptionManager.findJsonArrayFirstString(headerJson, 'Location');
    if (firstLocation.length > 0) {
      return SubscriptionManager.resolveUrl(currentUrl, firstLocation);
    }
    const firstLowerLocation = SubscriptionManager.findJsonArrayFirstString(headerJson, 'location');
    if (firstLowerLocation.length > 0) {
      return SubscriptionManager.resolveUrl(currentUrl, firstLowerLocation);
    }
    return '';
  }

  private static resolveUrl(currentUrl: string, location: string): string {
    const trimmed = location.trim();
    if (SubscriptionManager.isHttpUrl(trimmed)) {
      return trimmed;
    }
    const schemeEnd = currentUrl.indexOf('://');
    if (schemeEnd < 0) {
      return '';
    }
    const scheme = currentUrl.substring(0, schemeEnd);
    if (trimmed.startsWith('//')) {
      return `${scheme}:${trimmed}`;
    }
    const originEnd = currentUrl.indexOf('/', schemeEnd + 3);
    const origin = originEnd < 0 ? currentUrl : currentUrl.substring(0, originEnd);
    if (trimmed.startsWith('/')) {
      return `${origin}${trimmed}`;
    }
    const queryStart = currentUrl.indexOf('?');
    const withoutQuery = queryStart < 0 ? currentUrl : currentUrl.substring(0, queryStart);
    const slashIndex = withoutQuery.lastIndexOf('/');
    if (slashIndex <= schemeEnd + 2) {
      return `${origin}/${trimmed}`;
    }
    return `${withoutQuery.substring(0, slashIndex + 1)}${trimmed}`;
  }

  private static makeNodeName(imported: ShareLinkParseResult, outboundJson: string, index: number): string {
    if (imported.name.length > 0) {
      return imported.name;
    }
    const server = SubscriptionManager.describeServer(outboundJson);
    if (server.length > 0) {
      return `${imported.protocol.toUpperCase()} ${server}`;
    }
    return `${imported.protocol.toUpperCase()} #${index + 1}`;
  }

  private static describeServer(outboundJson: string): string {
    const address = SubscriptionManager.findJsonString(outboundJson, 'address');
    const port = SubscriptionManager.findJsonNumber(outboundJson, 'port');
    if (address.length > 0 && port.length > 0) {
      return `${address}:${port}`;
    }
    return '';
  }

  private static findJsonString(value: string, key: string): string {
    const start = SubscriptionManager.findJsonPropertyValueStart(value, key);
    if (start < 0) {
      return '';
    }
    let contentStart = start;
    while (contentStart < value.length && SubscriptionManager.isJsonWhitespace(value.charAt(contentStart))) {
      contentStart++;
    }
    if (contentStart >= value.length || value.charAt(contentStart) !== '"') {
      return '';
    }
    contentStart++;
    const contentEnd = value.indexOf('"', contentStart);
    if (contentEnd < contentStart) {
      return '';
    }
    return value.substring(contentStart, contentEnd);
  }

  private static findJsonNumber(value: string, key: string): string {
    const start = SubscriptionManager.findJsonPropertyValueStart(value, key);
    if (start < 0) {
      return '';
    }
    let index = start;
    while (index < value.length && SubscriptionManager.isJsonWhitespace(value.charAt(index))) {
      index++;
    }
    let result = '';
    while (index < value.length) {
      const ch = value.charAt(index);
      if (ch < '0' || ch > '9') {
        break;
      }
      result += ch;
      index++;
    }
    return result;
  }

  private static findJsonArrayFirstString(value: string, key: string): string {
    const start = SubscriptionManager.findJsonPropertyValueStart(value, key);
    if (start < 0) {
      return '';
    }
    let index = start;
    while (index < value.length && SubscriptionManager.isJsonWhitespace(value.charAt(index))) {
      index++;
    }
    if (index >= value.length || value.charAt(index) !== '[') {
      return '';
    }
    index++;
    while (index < value.length && SubscriptionManager.isJsonWhitespace(value.charAt(index))) {
      index++;
    }
    if (index >= value.length || value.charAt(index) !== '"') {
      return '';
    }
    const contentStart = index + 1;
    const contentEnd = value.indexOf('"', contentStart);
    if (contentEnd < contentStart) {
      return '';
    }
    return value.substring(contentStart, contentEnd);
  }

  private static findJsonPropertyValueStart(value: string, key: string): number {
    const marker = `"${key}"`;
    let start = value.indexOf(marker);
    while (start >= 0) {
      let index = start + marker.length;
      while (index < value.length && SubscriptionManager.isJsonWhitespace(value.charAt(index))) {
        index++;
      }
      if (index < value.length && value.charAt(index) === ':') {
        return index + 1;
      }
      start = value.indexOf(marker, start + marker.length);
    }
    return -1;
  }

  private static isJsonWhitespace(value: string): boolean {
    return value === ' ' || value === '\n' || value === '\r' || value === '\t';
  }

  private static makeNodeId(sourceUrl: string, rawLink: string): string {
    const value = `${sourceUrl}|${rawLink}`;
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash = (hash ^ value.charCodeAt(index)) * 16777619;
      hash = hash >>> 0;
    }
    return `node-${hash.toString(16)}`;
  }

  private static isHttpUrl(value: string): boolean {
    const lower = value.toLowerCase();
    return lower.startsWith('https://') || lower.startsWith('http://');
  }

  private static isInsecureHttpUrl(value: string): boolean {
    return value.toLowerCase().startsWith('http://');
  }
}
