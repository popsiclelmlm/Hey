import { ProxyNode } from '../../core/Profile';
import { normalizeConfigInput } from '../../core/XrayConfig';
import { formatOutboundJsonToShareLink } from '../../core/ShareLinkParser';

export type NodeSortKey = 'delay' | 'name' | 'protocol';

export interface NodeListState {
  query: string;
  sortKey: NodeSortKey;
  nodes: Array<ProxyNode>;
  selectedNodeId: string;
}

export interface NodeExportModel {
  title: string;
  content: string;
  count: number;
}

export function filterNodes(nodes: Array<ProxyNode>, query: string): Array<ProxyNode> {
  const keyword = query.trim().toLowerCase();
  if (keyword.length === 0) {
    return copyNodes(nodes);
  }

  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes[index];
    const value = `${node.name} ${node.protocol} ${node.sourceUrl}`.toLowerCase();
    if (value.indexOf(keyword) >= 0) {
      result.push(node);
    }
  }
  return result;
}

export function sortNodes(nodes: Array<ProxyNode>, sortKey: NodeSortKey): Array<ProxyNode> {
  const result = copyNodes(nodes);
  result.sort((left: ProxyNode, right: ProxyNode): number => {
    if (sortKey === 'delay') {
      return compareDelay(left, right);
    }
    if (sortKey === 'protocol') {
      return compareText(left.protocol, right.protocol) || compareText(left.name, right.name);
    }
    return compareText(left.name, right.name) || compareText(left.protocol, right.protocol);
  });
  return result;
}

export function filterAndSortNodes(nodes: Array<ProxyNode>, query: string, sortKey: NodeSortKey): Array<ProxyNode> {
  return sortNodes(filterNodes(nodes, query), sortKey);
}

export function dedupeNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const seen = new Set<string>();
  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes[index];
    const key = dedupeKey(node);
    if (key.length > 0 && seen.has(key)) {
      continue;
    }
    if (key.length > 0) {
      seen.add(key);
    }
    result.push(node);
  }
  return result;
}

export function findInvalidNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes[index];
    if (!normalizeConfigInput(node.outboundJson, node.configType).valid) {
      result.push(node);
    }
  }
  return result;
}

export function removeInvalidNodesFromList(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes[index];
    if (normalizeConfigInput(node.outboundJson, node.configType).valid) {
      result.push(node);
    }
  }
  return result;
}

// Drops nodes that failed their most recent delay test (timed out / errored).
// Untested nodes (empty status) and in-flight ones ('testing') are kept, so a
// post-test cleanup only removes nodes that were actually measured and failed.
export function removeTestFailedNodesFromList(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes[index];
    if (!isTestFailed(node)) {
      result.push(node);
    }
  }
  return result;
}

function isTestFailed(node: ProxyNode): boolean {
  if (node.delayMs >= 0) {
    return false;
  }
  const status = node.delayStatus;
  return status.length > 0 && status !== 'ok' && status !== 'testing';
}

export function exportNodesText(nodes: Array<ProxyNode>): string {
  const lines = new Array<string>();
  for (let index = 0; index < nodes.length; index++) {
    const value = exportNodeText(nodes[index]);
    if (value.length > 0) {
      lines.push(value);
    }
  }
  return lines.join('\n');
}

export function buildNodeExportModel(title: string, nodes: Array<ProxyNode>): NodeExportModel {
  return {
    title,
    content: exportNodesText(nodes),
    count: nodes.length
  };
}

function exportNodeText(node: ProxyNode): string {
  const rawLink = node.rawLink.trim();
  if (rawLink.length > 0) {
    return rawLink;
  }
  const link = formatOutboundJsonToShareLink(node.outboundJson, node.name);
  if (link.length > 0) {
    return link;
  }
  const validation = normalizeConfigInput(node.outboundJson, node.configType);
  if (validation.valid) {
    return validation.normalizedJson;
  }
  return node.outboundJson.trim();
}

function dedupeKey(node: ProxyNode): string {
  const rawLink = node.rawLink.trim();
  if (rawLink.length > 0) {
    return `raw:${rawLink}`;
  }
  const validation = normalizeConfigInput(node.outboundJson, node.configType);
  if (validation.valid) {
    return `json:${validation.normalizedJson}`;
  }
  return `json:${node.outboundJson.trim()}`;
}

function compareDelay(left: ProxyNode, right: ProxyNode): number {
  const leftRank = delayRank(left);
  const rightRank = delayRank(right);
  if (leftRank !== rightRank) {
    return leftRank - rightRank;
  }
  if (left.delayMs >= 0 && right.delayMs >= 0 && left.delayMs !== right.delayMs) {
    return left.delayMs - right.delayMs;
  }
  return compareText(left.name, right.name) || compareText(left.protocol, right.protocol);
}

function delayRank(node: ProxyNode): number {
  if (node.delayMs >= 0) {
    return 0;
  }
  if (node.delayStatus.length > 0) {
    return 1;
  }
  return 2;
}

function compareText(left: string, right: string): number {
  const normalizedLeft = left.toLowerCase();
  const normalizedRight = right.toLowerCase();
  if (normalizedLeft < normalizedRight) {
    return -1;
  }
  if (normalizedLeft > normalizedRight) {
    return 1;
  }
  return 0;
}

function copyNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    result.push(nodes[index]);
  }
  return result;
}
