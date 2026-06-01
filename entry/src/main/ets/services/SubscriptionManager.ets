import { http } from '@kit.NetworkKit';
import { ProxyNode } from '../core/Profile';
import { decodeBase64ToUtf8 } from '../core/Encoding';
import {
  isSupportedShareLink,
  parseShareLinkToOutboundJson,
  ShareLinkParseResult
} from '../core/ShareLinkParser';
import { normalizeOutboundInput } from '../core/XrayConfig';

export interface SubscriptionUpdateResult {
  ok: boolean;
  message: string;
  nodes: Array<ProxyNode>;
  rawLength: number;
}

interface OutboundPreview {
  protocol?: string;
  settings?: Object;
}

export class SubscriptionManager {
  static async fetchAndParse(url: string): Promise<SubscriptionUpdateResult> {
    const trimmedUrl = url.trim();
    if (!SubscriptionManager.isHttpUrl(trimmedUrl)) {
      return {
        ok: false,
        message: '订阅链接必须是 http:// 或 https://。',
        nodes: [],
        rawLength: 0
      };
    }

    const content = await SubscriptionManager.fetchText(trimmedUrl);
    const nodes = SubscriptionManager.parseSubscriptionContent(content, trimmedUrl);
    return {
      ok: nodes.length > 0,
      message: nodes.length > 0 ? `订阅更新完成，共 ${nodes.length} 个可用节点。` : '订阅内容里没有识别到支持的节点。',
      nodes,
      rawLength: content.length
    };
  }

  static parseSubscriptionContent(content: string, sourceUrl: string): Array<ProxyNode> {
    const rawNodes = SubscriptionManager.parseLines(content, sourceUrl);
    if (rawNodes.length > 0) {
      return rawNodes;
    }

    try {
      const decoded = decodeBase64ToUtf8(content);
      return SubscriptionManager.parseLines(decoded, sourceUrl);
    } catch (error) {
      return [];
    }
  }

  private static async fetchText(url: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 30000,
        connectTimeout: 15000,
        header: {
          'User-Agent': 'Hey/0.1 HarmonyOS NEXT Xray Client',
          'Accept': '*/*'
        }
      });
      if (Number(response.responseCode) < 200 || Number(response.responseCode) >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return response.result.toString();
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
    return {
      id: SubscriptionManager.makeNodeId(sourceUrl, line),
      name: SubscriptionManager.makeNodeName(imported, validation.normalizedJson, index),
      protocol: validation.protocol,
      outboundJson: validation.normalizedJson,
      sourceUrl,
      rawLink: line,
      updatedAt: now,
      delayMs: -1,
      delayTestAt: 0,
      delayStatus: ''
    };
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
    try {
      const outbound = JSON.parse(outboundJson) as OutboundPreview;
      const raw = JSON.stringify(outbound.settings);
      const address = SubscriptionManager.findJsonString(raw, '"address":"');
      const port = SubscriptionManager.findJsonNumber(raw, '"port":');
      if (address.length > 0 && port.length > 0) {
        return `${address}:${port}`;
      }
    } catch (error) {
      return '';
    }
    return '';
  }

  private static findJsonString(value: string, marker: string): string {
    const start = value.indexOf(marker);
    if (start < 0) {
      return '';
    }
    const contentStart = start + marker.length;
    const contentEnd = value.indexOf('"', contentStart);
    if (contentEnd < contentStart) {
      return '';
    }
    return value.substring(contentStart, contentEnd);
  }

  private static findJsonNumber(value: string, marker: string): string {
    const start = value.indexOf(marker);
    if (start < 0) {
      return '';
    }
    let index = start + marker.length;
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
}
