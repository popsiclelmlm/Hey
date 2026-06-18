import { ProxyNode, XrayConfigType } from './Profile';
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
  outbounds: Array<Object>;
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
