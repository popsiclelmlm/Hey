import { AppSettings, ProxyNode, SubscriptionGroup } from '../../core/Profile';
import { resolveDynamicPolicyGroupConfigJson } from '../../core/AdvancedOutboundBuilder';
import { buildRuntimeXrayConfig, normalizeConfigInput } from '../../core/XrayConfig';
import { formatOutboundJsonToShareLink } from '../../core/ShareLinkParser';
import { dedupeProxyNodes, proxyNodeDedupeKey } from '../../core/NodeDedupe';

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

export interface NodeFullConfigModel {
  success: boolean;
  content: string;
  message: string;
}

export interface NodeBatchMutationResult {
  groups: Array<SubscriptionGroup>;
  removedCount: number;
  sortedGroupCount: number;
}

export interface NodeMoveResult {
  groups: Array<SubscriptionGroup>;
  moved: boolean;
  groupId: string;
}

export interface NodeEndpoint {
  address: string;
  port: string;
}

interface NodeTestDelaySortEntry {
  node: ProxyNode;
  delay: number;
  originalIndex: number;
}

export function filterNodes(nodes: Array<ProxyNode>, query: string): Array<ProxyNode> {
  const keyword = query.trim();
  if (keyword.length === 0) {
    return copyNodes(nodes);
  }

  const regex = buildNodeSearchRegex(keyword);
  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes[index];
    if (matchesNodeSearch(node, keyword, regex)) {
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

function buildNodeSearchRegex(keyword: string): RegExp | null {
  try {
    return new RegExp(keyword, 'i');
  } catch (_error) {
    return null;
  }
}

function matchesNodeSearch(node: ProxyNode, keyword: string, regex: RegExp | null): boolean {
  const fields = nodeSearchFields(node);
  const literal = keyword.toLowerCase();
  for (let index = 0; index < fields.length; index++) {
    const value = fields[index];
    if (regex !== null) {
      if (regex.test(value)) {
        return true;
      }
    } else if (value.toLowerCase().indexOf(literal) >= 0) {
      return true;
    }
  }
  return false;
}

function nodeSearchFields(node: ProxyNode): Array<string> {
  const fields = new Array<string>();
  appendSearchField(fields, node.name);
  appendSearchField(fields, node.sourceUrl);
  appendSearchField(fields, buildV2rayNgNodeDescription(node));
  appendSearchField(fields, extractOutboundServer(node.outboundJson));
  appendSearchField(fields, node.protocol);
  return fields;
}

function appendSearchField(fields: Array<string>, value: string): void {
  const normalized = value.trim();
  if (normalized.length > 0) {
    fields.push(normalized);
  }
}

export function extractNodeEndpoint(outboundJson: string): NodeEndpoint {
  try {
    const outbound = JSON.parse(outboundJson) as Record<string, Object>;
    const protocol = stringValue(outbound['protocol']).toLowerCase();
    const settings = objectValue(outbound['settings']);
    if (settings === null) {
      return emptyNodeEndpoint();
    }
    if (protocol === 'vless' || protocol === 'vmess') {
      const server = firstRecord(settings['vnext']);
      return {
        address: stringValue(server?.['address']),
        port: stringValue(server?.['port'])
      };
    }
    if (protocol === 'wireguard') {
      return parseEndpointAddressAndPort(stringValue(firstRecord(settings['peers'])?.['endpoint']));
    }
    const server = firstRecord(settings['servers']);
    return {
      address: stringValue(server?.['address']),
      port: stringValue(server?.['port'])
    };
  } catch (_error) {
    return emptyNodeEndpoint();
  }
}

export function buildV2rayNgNodeDescription(node: ProxyNode): string {
  const endpoint = extractNodeEndpoint(node.outboundJson);
  return formatV2rayNgEndpointDescription(endpoint.address, endpoint.port);
}

export function formatV2rayNgEndpointDescription(address: string, port: string): string {
  const server = address.trim();
  const serverPort = port.trim();
  if (server.length === 0 && serverPort.length === 0) {
    return '';
  }
  return `${maskV2rayNgEndpointAddress(server)} : ${serverPort}`;
}

function extractOutboundServer(outboundJson: string): string {
  return extractNodeEndpoint(outboundJson).address;
}

function emptyNodeEndpoint(): NodeEndpoint {
  return {
    address: '',
    port: ''
  };
}

function firstRecord(value: Object | undefined): Record<string, Object> | null {
  if (!Array.isArray(value) || value.length === 0) {
    return null;
  }
  const values = value as Array<Object>;
  return objectValue(values[0]);
}

function objectValue(value: Object | undefined): Record<string, Object> | null {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, Object>;
}

function stringValue(value: Object | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return `${value}`;
  }
  return '';
}

function parseEndpointAddressAndPort(endpoint: string): NodeEndpoint {
  if (endpoint.startsWith('[')) {
    const endIndex = endpoint.indexOf(']');
    if (endIndex > 0) {
      const portStart = endpoint.indexOf(':', endIndex);
      return {
        address: endpoint.substring(1, endIndex),
        port: portStart >= 0 ? endpoint.substring(portStart + 1) : ''
      };
    }
  }
  const portIndex = endpoint.lastIndexOf(':');
  if (portIndex <= 0) {
    return {
      address: endpoint,
      port: ''
    };
  }
  return {
    address: endpoint.substring(0, portIndex),
    port: endpoint.substring(portIndex + 1)
  };
}

function maskV2rayNgEndpointAddress(address: string): string {
  if (address.length === 0) {
    return '';
  }
  if (address.indexOf(':') >= 0) {
    const parts = address.split(':');
    const visibleParts = new Array<string>();
    for (let index = 0; index < parts.length && index < 2; index++) {
      visibleParts.push(parts[index]);
    }
    return `${visibleParts.join(':')}:***`;
  }
  const parts = address.split('.');
  const visibleParts = new Array<string>();
  for (let index = 0; index < parts.length - 1; index++) {
    visibleParts.push(parts[index]);
  }
  return `${visibleParts.join('.')}.***`;
}

export function dedupeNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
  return dedupeProxyNodes(nodes);
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

export function removeVisibleNodesFromGroups(
  groups: Array<SubscriptionGroup>,
  visibleNodes: Array<ProxyNode>,
  updatedAt: number = 0
): NodeBatchMutationResult {
  return removeNodeIdsFromGroups(groups, nodeIdSet(visibleNodes), updatedAt);
}

export function removeVisibleTestFailedNodesFromGroups(
  groups: Array<SubscriptionGroup>,
  visibleNodes: Array<ProxyNode>,
  updatedAt: number = 0
): NodeBatchMutationResult {
  const failed = new Array<ProxyNode>();
  for (let index = 0; index < visibleNodes.length; index++) {
    if (isTestFailed(visibleNodes[index])) {
      failed.push(visibleNodes[index]);
    }
  }
  return removeVisibleNodesFromGroups(groups, failed, updatedAt);
}

export function moveNodeWithinGroup(
  groups: Array<SubscriptionGroup>,
  groupId: string,
  nodeId: string,
  delta: number,
  updatedAt: number = 0
): NodeMoveResult {
  const nextGroups = copySubscriptionGroups(groups);
  if (groupId.length === 0 || nodeId.length === 0 || delta === 0) {
    return { groups: nextGroups, moved: false, groupId };
  }

  for (let groupIndex = 0; groupIndex < nextGroups.length; groupIndex++) {
    const group = nextGroups[groupIndex];
    if (group.id !== groupId) {
      continue;
    }
    const fromIndex = findNodeIndex(group.nodes, nodeId);
    const toIndex = fromIndex + delta;
    if (fromIndex < 0 || toIndex < 0 || toIndex >= group.nodes.length) {
      return { groups: nextGroups, moved: false, groupId };
    }
    const moving = group.nodes[fromIndex];
    group.nodes[fromIndex] = group.nodes[toIndex];
    group.nodes[toIndex] = moving;
    group.updatedAt = updatedAt > 0 ? updatedAt : group.updatedAt;
    return { groups: nextGroups, moved: true, groupId };
  }
  return { groups: nextGroups, moved: false, groupId };
}

export function dedupeVisibleNodesInGroups(
  groups: Array<SubscriptionGroup>,
  visibleNodes: Array<ProxyNode>,
  updatedAt: number = 0
): NodeBatchMutationResult {
  const seen = new Set<string>();
  const duplicateIds = new Set<string>();
  for (let index = 0; index < visibleNodes.length; index++) {
    const node = visibleNodes[index];
    const key = proxyNodeDedupeKey(node);
    if (key.length === 0) {
      continue;
    }
    if (seen.has(key)) {
      duplicateIds.add(node.id);
    } else {
      seen.add(key);
    }
  }
  return removeNodeIdsFromGroups(groups, duplicateIds, updatedAt);
}

export function applyDelayTestPostActionsToGroups(
  groups: Array<SubscriptionGroup>,
  removeTargets: Array<ProxyNode>,
  sortTargets: Array<ProxyNode>,
  autoRemoveFailed: boolean,
  autoSort: boolean,
  updatedAt: number = 0
): NodeBatchMutationResult {
  let result: NodeBatchMutationResult = {
    groups: copySubscriptionGroups(groups),
    removedCount: 0,
    sortedGroupCount: 0
  };
  if (autoRemoveFailed) {
    result = removeVisibleTestFailedNodesFromGroups(result.groups, removeTargets, updatedAt);
  }
  if (!autoSort) {
    return result;
  }

  const sortedResult = sortGroupsByDelayTargets(result.groups, sortTargets, updatedAt);
  return {
    groups: sortedResult.groups,
    removedCount: result.removedCount,
    sortedGroupCount: sortedResult.sortedGroupCount
  };
}

export function sortGroupsByDelayTargets(
  groups: Array<SubscriptionGroup>,
  sortTargets: Array<ProxyNode>,
  updatedAt: number = 0
): NodeBatchMutationResult {
  const sortIds = nodeIdSet(sortTargets);
  const sortedGroups = new Array<SubscriptionGroup>();
  let sortedCount = 0;
  const sourceGroups = copySubscriptionGroups(groups);
  for (let index = 0; index < sourceGroups.length; index++) {
    const group = sourceGroups[index];
    if (containsAnyNodeId(group.nodes, sortIds)) {
      group.nodes = sortNodesByTestResults(group.nodes);
      group.selectedNodeId = resolveSelectedNodeId(group.nodes, group.selectedNodeId);
      group.updatedAt = updatedAt > 0 ? updatedAt : group.updatedAt;
      sortedCount++;
    }
    sortedGroups.push(group);
  }

  return {
    groups: sortedGroups,
    removedCount: 0,
    sortedGroupCount: sortedCount
  };
}

export function exportNodesText(nodes: Array<ProxyNode>): string {
  return exportNodeTexts(nodes).join('\n');
}

export function buildNodeExportModel(title: string, nodes: Array<ProxyNode>): NodeExportModel {
  const entries = exportNodeTexts(nodes);
  const content = entries.join('\n');
  return {
    title,
    content,
    count: entries.length
  };
}

function exportNodeTexts(nodes: Array<ProxyNode>): Array<string> {
  const lines = new Array<string>();
  for (let index = 0; index < nodes.length; index++) {
    const value = exportNodeText(nodes[index]);
    if (value.length > 0) {
      lines.push(value);
    }
  }
  return lines;
}

export function buildNodeFullConfigModel(
  node: ProxyNode,
  settings: AppSettings,
  groups: Array<SubscriptionGroup> = []
): NodeFullConfigModel {
  const validation = normalizeConfigInput(node.outboundJson, node.configType);
  if (!validation.valid) {
    return {
      success: false,
      content: '',
      message: validation.message
    };
  }

  try {
    const configJson = validation.configType === 'policy-group' ?
      resolveDynamicPolicyGroupConfigJson(validation.normalizedJson, groups) : validation.normalizedJson;
    const generated = buildRuntimeXrayConfig(configJson, settings, validation.configType);
    return {
      success: true,
      content: generated.configJson,
      message: ''
    };
  } catch (error) {
    const failed = error as Error;
    return {
      success: false,
      content: '',
      message: failed.message ?? JSON.stringify(error)
    };
  }
}

function exportNodeText(node: ProxyNode): string {
  if (isCustomExportNode(node)) {
    return '';
  }
  const rawLink = node.rawLink.trim();
  if (rawLink.length > 0) {
    return rawLink;
  }
  const link = formatOutboundJsonToShareLink(node.outboundJson, node.name);
  if (link.length > 0) {
    return link;
  }
  const validation = normalizeConfigInput(node.outboundJson, node.configType);
  if (validation.valid && !isCustomConfigType(validation.configType)) {
    return validation.normalizedJson;
  }
  return '';
}

function isCustomExportNode(node: ProxyNode): boolean {
  return isCustomConfigType(node.configType);
}

function isCustomConfigType(configType: string | undefined): boolean {
  return configType === 'full' || configType === 'proxy-chain' || configType === 'policy-group';
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

function sortNodesByTestResults(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const copied = copyNodes(nodes);
  const entries = new Array<NodeTestDelaySortEntry>();
  for (let index = 0; index < copied.length; index++) {
    entries.push({
      node: copied[index],
      delay: copied[index].delayMs > 0 ? copied[index].delayMs : 999999,
      originalIndex: index
    });
  }
  entries.sort((left: NodeTestDelaySortEntry, right: NodeTestDelaySortEntry): number => {
    if (left.delay !== right.delay) {
      return left.delay - right.delay;
    }
    return left.originalIndex - right.originalIndex;
  });
  const result = new Array<ProxyNode>();
  for (let index = 0; index < entries.length; index++) {
    result.push(entries[index].node);
  }
  return result;
}

function removeNodeIdsFromGroups(
  groups: Array<SubscriptionGroup>,
  ids: Set<string>,
  updatedAt: number
): NodeBatchMutationResult {
  const nextGroups = new Array<SubscriptionGroup>();
  let removedCount = 0;
  for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
    const group = copySubscriptionGroup(groups[groupIndex]);
    const nextNodes = new Array<ProxyNode>();
    let groupRemoved = 0;
    for (let nodeIndex = 0; nodeIndex < group.nodes.length; nodeIndex++) {
      const node = group.nodes[nodeIndex];
      if (ids.has(node.id)) {
        groupRemoved++;
      } else {
        nextNodes.push(node);
      }
    }
    if (groupRemoved > 0) {
      group.nodes = nextNodes;
      group.selectedNodeId = resolveSelectedNodeId(group.nodes, group.selectedNodeId);
      group.updatedAt = updatedAt > 0 ? updatedAt : group.updatedAt;
      removedCount += groupRemoved;
    }
    nextGroups.push(group);
  }
  return {
    groups: nextGroups,
    removedCount,
    sortedGroupCount: 0
  };
}

function nodeIdSet(nodes: Array<ProxyNode>): Set<string> {
  const ids = new Set<string>();
  for (let index = 0; index < nodes.length; index++) {
    ids.add(nodes[index].id);
  }
  return ids;
}

function containsAnyNodeId(nodes: Array<ProxyNode>, ids: Set<string>): boolean {
  for (let index = 0; index < nodes.length; index++) {
    if (ids.has(nodes[index].id)) {
      return true;
    }
  }
  return false;
}

function resolveSelectedNodeId(nodes: Array<ProxyNode>, selectedNodeId: string): string {
  for (let index = 0; index < nodes.length; index++) {
    if (nodes[index].id === selectedNodeId) {
      return selectedNodeId;
    }
  }
  return nodes.length > 0 ? nodes[0].id : '';
}

function findNodeIndex(nodes: Array<ProxyNode>, nodeId: string): number {
  for (let index = 0; index < nodes.length; index++) {
    if (nodes[index].id === nodeId) {
      return index;
    }
  }
  return -1;
}

function copySubscriptionGroups(groups: Array<SubscriptionGroup>): Array<SubscriptionGroup> {
  const copied = new Array<SubscriptionGroup>();
  for (let index = 0; index < groups.length; index++) {
    copied.push(copySubscriptionGroup(groups[index]));
  }
  return copied;
}

function copySubscriptionGroup(group: SubscriptionGroup): SubscriptionGroup {
  return {
    id: group.id,
    name: group.name,
    url: group.url,
    enabled: group.enabled,
    selectedNodeId: group.selectedNodeId,
    nodes: copyNodes(group.nodes),
    updatedAt: group.updatedAt,
    userAgent: group.userAgent,
    filter: group.filter,
    prevProfile: group.prevProfile,
    nextProfile: group.nextProfile,
    allowInsecureUrl: group.allowInsecureUrl,
    autoUpdate: group.autoUpdate,
    updateIntervalMinutes: group.updateIntervalMinutes
  };
}

function copyNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const result = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    result.push(nodes[index]);
  }
  return result;
}
