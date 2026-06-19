import { ProxyNode, SubscriptionGroup, XrayConfigType } from './Profile';
import { normalizeConfigInput } from './XrayConfig';

export type PolicyGroupStrategy = 'roundRobin' | 'random' | 'leastPing' | 'leastLoad';

export interface AdvancedOutboundBuildResult {
  success: boolean;
  message: string;
  configJson: string;
  configType: XrayConfigType;
  protocol: string;
  name: string;
  count: number;
}

export interface AdvancedOutboundEditState {
  success: boolean;
  message: string;
  mode: XrayConfigType;
  name: string;
  strategy: PolicyGroupStrategy;
  dynamicPolicyGroupEnabled: boolean;
  dynamicSubscriptionId: string;
  dynamicFilter: string;
  memberOutboundJsons: Array<string>;
}

interface AdvancedOutboundMember {
  outboundJson: string;
}

interface AdvancedOutboundMemberResult {
  success: boolean;
  message: string;
  members: Array<AdvancedOutboundMember>;
}

interface ProxyChainStorageConfig {
  remarks: string;
  outbounds: Array<Object>;
}

interface PolicyGroupStorageConfig {
  type: string;
  remarks: string;
  strategy: string;
  policyGroupSubscriptionId?: string;
  policyGroupFilter?: string;
  outbounds: Array<Object>;
}

export interface AdvancedOutboundSourceNode {
  groupId: string;
  node: ProxyNode;
}

export function buildProxyChainConfigFromNodes(name: string, nodes: Array<ProxyNode>): AdvancedOutboundBuildResult {
  const memberResult = normalizeAdvancedOutboundMembers(nodes);
  if (!memberResult.success) {
    return failedBuild('proxy-chain', memberResult.message, name, memberResult.members.length);
  }
  const members = memberResult.members;
  if (members.length < 2) {
    return failedBuild('proxy-chain', '代理链至少需要两个普通 outbound 节点。', name, members.length);
  }

  const config: ProxyChainStorageConfig = {
    remarks: resolveAdvancedOutboundName(name, '代理链'),
    outbounds: buildMemberOutbounds(members)
  };
  return validateBuiltConfig('proxy-chain', config.remarks, JSON.stringify(config, null, 2), members.length);
}

export function buildPolicyGroupConfigFromNodes(name: string, strategy: string, nodes: Array<ProxyNode>): AdvancedOutboundBuildResult {
  return buildPolicyGroupConfigFromNodesInternal(name, strategy, nodes, '', '', false);
}

export function buildDynamicPolicyGroupConfigFromNodes(
  name: string,
  strategy: string,
  subscriptionId: string,
  filter: string,
  nodes: Array<ProxyNode>
): AdvancedOutboundBuildResult {
  return buildPolicyGroupConfigFromNodesInternal(name, strategy, nodes, subscriptionId, filter, true);
}

export function buildPolicyGroupConfigFromSubscription(
  name: string,
  strategy: string,
  subscriptionId: string,
  filter: string,
  groups: Array<SubscriptionGroup>
): AdvancedOutboundBuildResult {
  const sources = collectPolicyGroupSourceNodes(groups, subscriptionId, filter);
  const nodes = new Array<ProxyNode>();
  for (let index = 0; index < sources.length; index++) {
    nodes.push(sources[index].node);
  }
  return buildDynamicPolicyGroupConfigFromNodes(name, strategy, subscriptionId, filter, nodes);
}

export function collectPolicyGroupSourceNodes(groups: Array<SubscriptionGroup>, subscriptionId: string, filter: string): Array<AdvancedOutboundSourceNode> {
  const result = new Array<AdvancedOutboundSourceNode>();
  const normalizedSubscriptionId = subscriptionId.trim();
  for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
    const group = groups[groupIndex];
    if (normalizedSubscriptionId.length > 0 && group.id !== normalizedSubscriptionId) {
      continue;
    }
    for (let nodeIndex = 0; nodeIndex < group.nodes.length; nodeIndex++) {
      const node = group.nodes[nodeIndex];
      if (isAdvancedOutboundBuildableNode(node) && matchesPolicyGroupFilter(node.name, filter)) {
        result.push({
          groupId: group.id,
          node
        });
      }
    }
  }
  return result;
}

export function resolveDynamicPolicyGroupConfigJson(configJson: string, groups: Array<SubscriptionGroup>): string {
  const dynamic = parseDynamicPolicyGroupConfig(configJson);
  if (dynamic === null) {
    return configJson;
  }
  const sourceNodes = collectPolicyGroupSourceNodes(groups, dynamic.subscriptionId, dynamic.filter);
  const nodes = new Array<ProxyNode>();
  for (let index = 0; index < sourceNodes.length; index++) {
    nodes.push(sourceNodes[index].node);
  }
  const result = buildDynamicPolicyGroupConfigFromNodes(dynamic.name, dynamic.strategy, dynamic.subscriptionId, dynamic.filter, nodes);
  return result.success ? result.configJson : configJson;
}

export function parseAdvancedOutboundEditState(configJson: string, configType?: XrayConfigType): AdvancedOutboundEditState {
  const validation = normalizeConfigInput(configJson, configType);
  const mode = validation.configType ?? configType ?? 'proxy-chain';
  if (!validation.valid || (mode !== 'proxy-chain' && mode !== 'policy-group')) {
    return emptyAdvancedOutboundEditState(mode, validation.message);
  }

  try {
    const parsed = JSON.parse(validation.normalizedJson) as Record<string, Object>;
    const rawOutbounds = parsed['outbounds'];
    if (!Array.isArray(rawOutbounds)) {
      return emptyAdvancedOutboundEditState(mode, mode === 'policy-group' ? '策略组配置缺少 outbounds 数组。' : '代理链配置缺少 outbounds 数组。');
    }

    const memberOutboundJsons = new Array<string>();
    for (let index = 0; index < rawOutbounds.length; index++) {
      const memberJson = normalizeAdvancedOutboundMemberJson(JSON.stringify(rawOutbounds[index]));
      if (memberJson.length > 0) {
        memberOutboundJsons.push(memberJson);
      }
    }

    const dynamicSubscriptionId = stringRecordValue(parsed, 'policyGroupSubscriptionId');
    const dynamicFilter = stringRecordValue(parsed, 'policyGroupFilter');
    return {
      success: true,
      message: validation.message,
      mode,
      name: resolveAdvancedOutboundEditName(parsed, mode),
      strategy: mode === 'policy-group' ? normalizePolicyGroupBuilderStrategy(stringRecordValue(parsed, 'strategy', stringRecordValue(parsed, 'policyGroupType'))) : 'roundRobin',
      dynamicPolicyGroupEnabled: mode === 'policy-group' && (dynamicSubscriptionId.length > 0 || dynamicFilter.length > 0 || hasRecordKey(parsed, 'policyGroupSubscriptionId') || hasRecordKey(parsed, 'policyGroupFilter')),
      dynamicSubscriptionId,
      dynamicFilter,
      memberOutboundJsons
    };
  } catch (error) {
    return emptyAdvancedOutboundEditState(mode, `高级节点配置解析失败：${JSON.stringify(error)}`);
  }
}

export function normalizeAdvancedOutboundMemberJson(outboundJson: string): string {
  const validation = normalizeConfigInput(outboundJson, 'outbound');
  if (validation.valid && validation.configType === 'outbound') {
    return validation.normalizedJson;
  }
  return '';
}

function buildPolicyGroupConfigFromNodesInternal(name: string, strategy: string, nodes: Array<ProxyNode>, subscriptionId: string, filter: string, dynamicSource: boolean): AdvancedOutboundBuildResult {
  const memberResult = normalizeAdvancedOutboundMembers(nodes);
  if (!memberResult.success) {
    return failedBuild('policy-group', memberResult.message, name, memberResult.members.length);
  }
  const members = memberResult.members;
  if (members.length < 1) {
    return failedBuild('policy-group', '策略组至少需要一个普通 outbound 节点。', name, members.length);
  }

  const config: PolicyGroupStorageConfig = {
    type: 'policy-group',
    remarks: resolveAdvancedOutboundName(name, '策略组'),
    strategy: normalizePolicyGroupBuilderStrategy(strategy),
    outbounds: buildMemberOutbounds(members)
  };
  const normalizedSubscriptionId = subscriptionId.trim();
  const normalizedFilter = filter.trim();
  if (dynamicSource || normalizedSubscriptionId.length > 0) {
    config.policyGroupSubscriptionId = normalizedSubscriptionId;
  }
  if (dynamicSource || normalizedFilter.length > 0) {
    config.policyGroupFilter = normalizedFilter;
  }
  return validateBuiltConfig('policy-group', config.remarks, JSON.stringify(config, null, 2), members.length);
}

export function normalizePolicyGroupBuilderStrategy(strategy: string): PolicyGroupStrategy {
  const normalized = strategy.trim();
  if (normalized === 'random') {
    return 'random';
  }
  if (normalized === 'leastPing' || normalized === '0') {
    return 'leastPing';
  }
  if (normalized === 'leastLoad' || normalized === '1') {
    return 'leastLoad';
  }
  return 'roundRobin';
}

export function isAdvancedOutboundBuildableNode(node: ProxyNode): boolean {
  return normalizeAdvancedOutboundMember(node) !== null;
}

function normalizeAdvancedOutboundMembers(nodes: Array<ProxyNode>): AdvancedOutboundMemberResult {
  const members = new Array<AdvancedOutboundMember>();
  for (let index = 0; index < nodes.length; index++) {
    const member = normalizeAdvancedOutboundMember(nodes[index]);
    if (member === null) {
      return {
        success: false,
        message: `第 ${index + 1} 个节点不是可用的普通 outbound，不能加入高级节点。`,
        members
      };
    }
    members.push(member);
  }
  return {
    success: true,
    message: '',
    members
  };
}

function normalizeAdvancedOutboundMember(node: ProxyNode): AdvancedOutboundMember | null {
  const validation = normalizeConfigInput(node.outboundJson, node.configType);
  if (!validation.valid || validation.configType !== 'outbound') {
    return null;
  }
  return {
    outboundJson: validation.normalizedJson
  };
}

function buildMemberOutbounds(members: Array<AdvancedOutboundMember>): Array<Object> {
  const outbounds = new Array<Object>();
  for (let index = 0; index < members.length; index++) {
    outbounds.push(JSON.parse(members[index].outboundJson) as Object);
  }
  return outbounds;
}

interface DynamicPolicyGroupConfig {
  name: string;
  strategy: string;
  subscriptionId: string;
  filter: string;
}

function parseDynamicPolicyGroupConfig(configJson: string): DynamicPolicyGroupConfig | null {
  try {
    const parsed = JSON.parse(configJson) as Record<string, Object>;
    const type = typeof parsed.type === 'string' ? parsed.type : '';
    const configType = typeof parsed.configType === 'string' ? parsed.configType : '';
    if (type !== 'policy-group' && configType !== 'policy-group') {
      return null;
    }
    const hasSubscriptionId = typeof parsed.policyGroupSubscriptionId === 'string';
    const hasFilter = typeof parsed.policyGroupFilter === 'string';
    if (!hasSubscriptionId && !hasFilter) {
      return null;
    }
    const subscriptionId = typeof parsed.policyGroupSubscriptionId === 'string' ? parsed.policyGroupSubscriptionId.trim() : '';
    const filter = typeof parsed.policyGroupFilter === 'string' ? parsed.policyGroupFilter.trim() : '';
    return {
      name: resolveDynamicPolicyGroupName(parsed),
      strategy: typeof parsed.strategy === 'string' ? parsed.strategy : (typeof parsed.policyGroupType === 'string' ? parsed.policyGroupType : 'roundRobin'),
      subscriptionId,
      filter
    };
  } catch (error) {
    return null;
  }
}

function resolveDynamicPolicyGroupName(parsed: Record<string, Object>): string {
  if (typeof parsed.remarks === 'string' && parsed.remarks.trim().length > 0) {
    return parsed.remarks.trim();
  }
  if (typeof parsed.name === 'string' && parsed.name.trim().length > 0) {
    return parsed.name.trim();
  }
  return '策略组';
}

function resolveAdvancedOutboundEditName(parsed: Record<string, Object>, mode: XrayConfigType): string {
  if (typeof parsed.remarks === 'string' && parsed.remarks.trim().length > 0) {
    return parsed.remarks.trim();
  }
  if (typeof parsed.name === 'string' && parsed.name.trim().length > 0) {
    return parsed.name.trim();
  }
  return mode === 'policy-group' ? '策略组' : '代理链';
}

function emptyAdvancedOutboundEditState(mode: XrayConfigType, message: string): AdvancedOutboundEditState {
  return {
    success: false,
    message,
    mode,
    name: '',
    strategy: 'roundRobin',
    dynamicPolicyGroupEnabled: false,
    dynamicSubscriptionId: '',
    dynamicFilter: '',
    memberOutboundJsons: []
  };
}

function stringRecordValue(record: Record<string, Object>, key: string, fallback: string = ''): string {
  const value = record[key];
  return typeof value === 'string' ? value.trim() : fallback;
}

function hasRecordKey(record: Record<string, Object>, key: string): boolean {
  return record[key] !== undefined;
}

function matchesPolicyGroupFilter(name: string, filter: string): boolean {
  const normalized = filter.trim();
  if (normalized.length === 0) {
    return true;
  }
  try {
    return new RegExp(normalized, 'i').test(name);
  } catch (error) {
    return name.toLowerCase().indexOf(normalized.toLowerCase()) >= 0;
  }
}

function validateBuiltConfig(configType: XrayConfigType, name: string, configJson: string, count: number): AdvancedOutboundBuildResult {
  const validation = normalizeConfigInput(configJson, configType);
  if (!validation.valid) {
    return {
      success: false,
      message: validation.message,
      configJson: '',
      configType,
      protocol: configType,
      name,
      count
    };
  }
  return {
    success: true,
    message: validation.message,
    configJson: validation.normalizedJson,
    configType: validation.configType ?? configType,
    protocol: validation.protocol,
    name,
    count
  };
}

function failedBuild(configType: XrayConfigType, message: string, name: string, count: number): AdvancedOutboundBuildResult {
  return {
    success: false,
    message,
    configJson: '',
    configType,
    protocol: configType,
    name: resolveAdvancedOutboundName(name, configType === 'proxy-chain' ? '代理链' : '策略组'),
    count
  };
}

function resolveAdvancedOutboundName(name: string, fallback: string): string {
  const trimmed = name.trim();
  return trimmed.length > 0 ? trimmed : fallback;
}
