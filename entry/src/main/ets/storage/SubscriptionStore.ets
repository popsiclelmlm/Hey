import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ProxyNode, SubscriptionGroup, SubscriptionProfile, XrayConfigType } from '../core/Profile';
import { dedupeProxyNodes } from '../core/NodeDedupe';
import {
  DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  moveSubscriptionGroup,
  normalizeSubscriptionUpdateInterval
} from '../core/SubscriptionGroups';
import { resolveRetainedSelectedNodeId } from '../core/SubscriptionSelection';
import { normalizeConfigInput } from '../core/XrayConfig';

const PREFERENCES_NAME: string = 'hey_vpn_subscription';
const SUBSCRIPTION_KEY: string = 'subscription_profile';

export interface ManualNodeUpdateResult {
  updated: boolean;
  selected: boolean;
  node: ProxyNode | null;
  profile: SubscriptionProfile;
}

// 批量延迟落库的单条更新。
export interface NodeDelayUpdate {
  nodeId: string;
  delayMs: number;
  delayStatus: string;
  delayTestAt: number;
}

export class SubscriptionStore {
  static async load(context: common.Context): Promise<SubscriptionProfile> {
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    const rawValue = await store.get(SUBSCRIPTION_KEY, '');
    const raw = rawValue.toString();
    if (raw.length === 0) {
      return SubscriptionStore.createEmpty();
    }

    try {
      return SubscriptionStore.normalize(JSON.parse(raw) as SubscriptionProfile);
    } catch (error) {
      return SubscriptionStore.createEmpty();
    }
  }

  static async saveUrl(context: common.Context, url: string, groupId?: string, touchUpdatedAt: boolean = true): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    let group: SubscriptionGroup | null = null;
    if (groupId && groupId.length > 0) {
      group = SubscriptionStore.findGroup(profile.groups, groupId);
    }
    if (group === null) {
      group = SubscriptionStore.activeGroup(profile);
    }
    if (group === null) {
      group = SubscriptionStore.createGroup(url, SubscriptionStore.nameFromUrl(url));
      profile.groups.push(group);
      profile.selectedGroupId = group.id;
    }
    group.url = url;
    if (group.name.length === 0 || group.name.startsWith('Subscription ')) {
      group.name = SubscriptionStore.nameFromUrl(url);
    }
    if (touchUpdatedAt) {
      group.updatedAt = Date.now();
    }
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async saveNodes(context: common.Context, groupId: string, url: string, nodes: Array<ProxyNode>, selectedNodeId: string, makeActive: boolean = true): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    let group: SubscriptionGroup | null = null;
    if (groupId.length > 0) {
      group = SubscriptionStore.findGroup(profile.groups, groupId);
    }
    if (group === null) {
      group = SubscriptionStore.findGroupByUrl(profile.groups, url);
    }
    if (group === null) {
      group = SubscriptionStore.activeGroup(profile);
    }
    if (group === null) {
      group = SubscriptionStore.createGroup(url, SubscriptionStore.nameFromUrl(url));
      profile.groups.push(group);
    }

    const previousNodes = group.nodes;
    const mergedNodes = SubscriptionStore.mergeNodeRuntime(previousNodes, nodes);
    group.url = url;
    group.nodes = mergedNodes;
    group.selectedNodeId = resolveRetainedSelectedNodeId(previousNodes, mergedNodes, selectedNodeId);
    group.updatedAt = Date.now();
    if (makeActive) {
      profile.selectedGroupId = group.id;
    }
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async saveNodeDelay(context: common.Context, nodeId: string, delayMs: number, delayStatus: string, delayTestAt: number): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    for (let groupIndex = 0; groupIndex < profile.groups.length; groupIndex++) {
      const group = profile.groups[groupIndex];
      for (let nodeIndex = 0; nodeIndex < group.nodes.length; nodeIndex++) {
        if (group.nodes[nodeIndex].id === nodeId) {
          group.nodes[nodeIndex].delayMs = delayMs;
          group.nodes[nodeIndex].delayStatus = delayStatus;
          group.nodes[nodeIndex].delayTestAt = delayTestAt;
        }
      }
    }
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  // 批量落库一组节点的延迟结果：一次 load/save 写完整块，避免逐节点反复读写
  // preferences（大列表分块测速时每块只写一次）。
  static async saveNodeDelays(context: common.Context, updates: Array<NodeDelayUpdate>): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const byId = new Map<string, NodeDelayUpdate>();
    for (let i = 0; i < updates.length; i++) {
      byId.set(updates[i].nodeId, updates[i]);
    }
    for (let groupIndex = 0; groupIndex < profile.groups.length; groupIndex++) {
      const group = profile.groups[groupIndex];
      for (let nodeIndex = 0; nodeIndex < group.nodes.length; nodeIndex++) {
        const update = byId.get(group.nodes[nodeIndex].id);
        if (update !== undefined) {
          group.nodes[nodeIndex].delayMs = update.delayMs;
          group.nodes[nodeIndex].delayStatus = update.delayStatus;
          group.nodes[nodeIndex].delayTestAt = update.delayTestAt;
        }
      }
    }
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async saveActiveGroupNodes(context: common.Context, nodes: Array<ProxyNode>, selectedNodeId: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const group = SubscriptionStore.activeGroup(profile);
    if (group !== null) {
      group.nodes = SubscriptionStore.normalizeNodes(nodes);
      group.selectedNodeId = SubscriptionStore.resolveSelectedNodeId(group.nodes, selectedNodeId);
      group.updatedAt = Date.now();
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async saveGroups(context: common.Context, groups: Array<SubscriptionGroup>): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    profile.groups = groups;
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async removeNode(context: common.Context, nodeId: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    let removed = false;
    for (let groupIndex = 0; groupIndex < profile.groups.length; groupIndex++) {
      const group = profile.groups[groupIndex];
      const nodes = new Array<ProxyNode>();
      for (let index = 0; index < group.nodes.length; index++) {
        if (group.nodes[index].id !== nodeId) {
          nodes.push(group.nodes[index]);
        }
      }
      if (nodes.length !== group.nodes.length) {
        group.nodes = nodes;
        group.selectedNodeId = SubscriptionStore.resolveSelectedNodeId(nodes, group.selectedNodeId);
        group.updatedAt = Date.now();
        removed = true;
      }
    }
    if (removed) {
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async removeInvalidNodes(context: common.Context): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const group = SubscriptionStore.activeGroup(profile);
    if (group !== null) {
      const nodes = new Array<ProxyNode>();
      for (let index = 0; index < group.nodes.length; index++) {
        const node = group.nodes[index];
        if (normalizeConfigInput(node.outboundJson, node.configType).valid) {
          nodes.push(node);
        }
      }
      group.nodes = nodes;
      group.selectedNodeId = SubscriptionStore.resolveSelectedNodeId(nodes, group.selectedNodeId);
      group.updatedAt = Date.now();
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async dedupeActiveGroupNodes(context: common.Context): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const group = SubscriptionStore.activeGroup(profile);
    if (group !== null) {
      group.nodes = SubscriptionStore.dedupeNodes(group.nodes);
      group.selectedNodeId = SubscriptionStore.resolveSelectedNodeId(group.nodes, group.selectedNodeId);
      group.updatedAt = Date.now();
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async clearActiveGroupNodes(context: common.Context): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const group = SubscriptionStore.activeGroup(profile);
    if (group !== null) {
      group.nodes = [];
      group.selectedNodeId = '';
      group.updatedAt = Date.now();
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async selectNode(context: common.Context, selectedNodeId: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    for (let index = 0; index < profile.groups.length; index++) {
      const group = profile.groups[index];
      if (SubscriptionStore.findNode(group.nodes, selectedNodeId) !== null) {
        group.selectedNodeId = selectedNodeId;
        profile.selectedGroupId = group.id;
        await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
        return SubscriptionStore.load(context);
      }
    }

    profile.selectedNodeId = selectedNodeId;
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async selectGroup(context: common.Context, groupId: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    if (SubscriptionStore.findGroup(profile.groups, groupId) !== null) {
      profile.selectedGroupId = groupId;
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async toggleGroup(context: common.Context, groupId: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const group = SubscriptionStore.findGroup(profile.groups, groupId);
    if (group !== null) {
      group.enabled = !group.enabled;
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async removeGroup(context: common.Context, groupId: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const groups: Array<SubscriptionGroup> = [];
    for (let index = 0; index < profile.groups.length; index++) {
      if (profile.groups[index].id !== groupId) {
        groups.push(profile.groups[index]);
      }
    }
    profile.groups = groups;
    if (SubscriptionStore.findGroup(profile.groups, profile.selectedGroupId) === null) {
      profile.selectedGroupId = profile.groups.length > 0 ? profile.groups[0].id : '';
    }
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async moveGroup(context: common.Context, groupId: string, delta: number): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    profile.groups = moveSubscriptionGroup(profile.groups, groupId, delta);
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async addGroup(
    context: common.Context,
    name: string,
    url: string,
    userAgent: string = '',
    filter: string = '',
    prevProfile: string = '',
    nextProfile: string = '',
    allowInsecureUrl: boolean = false,
    autoUpdate: boolean = false,
    updateIntervalMinutes: number = DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
  ): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const group = SubscriptionStore.createGroup(url, name, userAgent, filter, prevProfile, nextProfile, allowInsecureUrl, autoUpdate, updateIntervalMinutes);
    profile.groups.push(group);
    profile.selectedGroupId = group.id;
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async updateGroup(
    context: common.Context,
    groupId: string,
    name: string,
    url: string,
    userAgent: string = '',
    filter: string = '',
    prevProfile: string = '',
    nextProfile: string = '',
    allowInsecureUrl: boolean = false,
    autoUpdate: boolean = false,
    updateIntervalMinutes: number = DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
  ): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    const group = SubscriptionStore.findGroup(profile.groups, groupId);
    if (group !== null) {
      group.name = name;
      group.url = url;
      group.userAgent = userAgent;
      group.filter = filter;
      group.prevProfile = prevProfile;
      group.nextProfile = nextProfile;
      group.allowInsecureUrl = allowInsecureUrl;
      group.autoUpdate = autoUpdate;
      group.updateIntervalMinutes = normalizeSubscriptionUpdateInterval(updateIntervalMinutes);
      await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    }
    return SubscriptionStore.load(context);
  }

  static async addManualNode(context: common.Context, name: string, outboundJson: string, configType?: XrayConfigType): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    
    let localGroup = SubscriptionStore.findGroup(profile.groups, 'sub-local');
    if (localGroup === null) {
      localGroup = {
        id: 'sub-local',
        name: '手动导入',
        url: '',
        enabled: true,
        selectedNodeId: '',
        nodes: [],
        updatedAt: Date.now(),
        userAgent: '',
        filter: '',
        prevProfile: '',
        nextProfile: '',
        allowInsecureUrl: false,
        autoUpdate: false,
        updateIntervalMinutes: DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
      };
      profile.groups.push(localGroup);
    }
    
    const validation = normalizeConfigInput(outboundJson, configType);
    const resolvedConfigType = SubscriptionStore.resolveConfigType(validation.configType, configType);
    const protocol = validation.valid ? SubscriptionStore.protocolForConfigType(resolvedConfigType, validation.protocol) : 'unknown';
    
    const nodeId = `manual-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    const finalName = name.trim().length > 0 ? name.trim() : `手动-${protocol.toUpperCase()}`;
    
    const newNode: ProxyNode = {
      id: nodeId,
      name: finalName,
      protocol: protocol,
      outboundJson: validation.valid ? validation.normalizedJson : outboundJson,
      configType: resolvedConfigType,
      sourceUrl: '',
      rawLink: '',
      updatedAt: Date.now(),
      delayMs: -1,
      delayTestAt: 0,
      delayStatus: ''
    };
    
    localGroup.nodes.push(newNode);
    localGroup.selectedNodeId = nodeId;
    localGroup.updatedAt = Date.now();
    
    profile.selectedGroupId = 'sub-local';
    profile.selectedNodeId = nodeId;
    
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async updateManualNode(context: common.Context, nodeId: string, name: string, outboundJson: string, configType?: XrayConfigType): Promise<ManualNodeUpdateResult> {
    const profile = await SubscriptionStore.load(context);
    const validation = normalizeConfigInput(outboundJson, configType);
    const resolvedConfigType = SubscriptionStore.resolveConfigType(validation.configType, configType);
    const protocol = validation.valid ? SubscriptionStore.protocolForConfigType(resolvedConfigType, validation.protocol) : 'unknown';
    const normalizedJson = validation.valid ? validation.normalizedJson : outboundJson;
    const now = Date.now();
    let selected = false;

    for (let groupIndex = 0; groupIndex < profile.groups.length; groupIndex++) {
      const group = profile.groups[groupIndex];
      for (let nodeIndex = 0; nodeIndex < group.nodes.length; nodeIndex++) {
        const node = group.nodes[nodeIndex];
        if (node.id !== nodeId) {
          continue;
        }
        if (node.sourceUrl.trim().length > 0 || node.rawLink.trim().length > 0) {
          return {
            updated: false,
            selected: false,
            node: null,
            profile
          };
        }
        const finalName = name.trim().length > 0 ? name.trim() : (node.name.length > 0 ? node.name : `手动-${protocol.toUpperCase()}`);
        const nextNode: ProxyNode = {
          id: node.id,
          name: finalName,
          protocol,
          outboundJson: normalizedJson,
          configType: resolvedConfigType,
          sourceUrl: '',
          rawLink: '',
          updatedAt: now,
          delayMs: -1,
          delayTestAt: 0,
          delayStatus: ''
        };
        group.nodes[nodeIndex] = nextNode;
        group.updatedAt = now;
        selected = profile.selectedNodeId === nodeId || group.selectedNodeId === nodeId;
        await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
        return {
          updated: true,
          selected,
          node: nextNode,
          profile: await SubscriptionStore.load(context)
        };
      }
    }

    return {
      updated: false,
      selected: false,
      node: null,
      profile
    };
  }

  private static async save(context: common.Context, profile: SubscriptionProfile): Promise<void> {
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    await store.put(SUBSCRIPTION_KEY, JSON.stringify(profile));
    await store.flush();
  }

  private static normalize(raw: SubscriptionProfile): SubscriptionProfile {
    const profile: SubscriptionProfile = {
      url: raw.url ?? '',
      selectedNodeId: raw.selectedNodeId ?? '',
      nodes: raw.nodes ?? [],
      updatedAt: raw.updatedAt ?? 0,
      selectedGroupId: raw.selectedGroupId ?? '',
      groups: raw.groups ?? []
    };

    const normalizedGroups: Array<SubscriptionGroup> = [];
    for (let index = 0; index < profile.groups.length; index++) {
      normalizedGroups.push(SubscriptionStore.normalizeGroup(profile.groups[index], index));
    }

    if (normalizedGroups.length === 0 && (profile.url.length > 0 || profile.nodes.length > 0)) {
      normalizedGroups.push({
        id: SubscriptionStore.makeGroupId(profile.url.length > 0 ? profile.url : 'legacy'),
        name: SubscriptionStore.nameFromUrl(profile.url),
        url: profile.url,
        enabled: true,
        selectedNodeId: profile.selectedNodeId,
        nodes: SubscriptionStore.normalizeNodes(profile.nodes),
        updatedAt: profile.updatedAt,
        userAgent: '',
        filter: '',
        prevProfile: '',
        nextProfile: '',
        allowInsecureUrl: false,
        autoUpdate: false,
        updateIntervalMinutes: DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
      });
    }

    profile.groups = normalizedGroups;
    if (SubscriptionStore.findGroup(profile.groups, profile.selectedGroupId) === null) {
      profile.selectedGroupId = profile.groups.length > 0 ? profile.groups[0].id : '';
    }

    const active = SubscriptionStore.activeGroup(profile);
    if (active !== null) {
      profile.url = active.url;
      profile.nodes = active.nodes;
      profile.selectedNodeId = active.selectedNodeId;
      profile.updatedAt = active.updatedAt;
    } else {
      profile.url = '';
      profile.nodes = [];
      profile.selectedNodeId = '';
      profile.updatedAt = 0;
    }
    return profile;
  }

  private static normalizeGroup(group: SubscriptionGroup, index: number): SubscriptionGroup {
    const url = group.url ?? '';
    const nodes = SubscriptionStore.normalizeNodes(group.nodes ?? []);
    return {
      id: group.id ?? SubscriptionStore.makeGroupId(`${url}-${index}`),
      name: group.name ?? SubscriptionStore.nameFromUrl(url),
      url,
      enabled: group.enabled ?? true,
      selectedNodeId: SubscriptionStore.resolveSelectedNodeId(nodes, group.selectedNodeId ?? ''),
      nodes,
      updatedAt: group.updatedAt ?? 0,
      userAgent: group.userAgent ?? '',
      filter: group.filter ?? '',
      prevProfile: group.prevProfile ?? '',
      nextProfile: group.nextProfile ?? '',
      allowInsecureUrl: group.allowInsecureUrl ?? false,
      autoUpdate: group.autoUpdate ?? false,
      updateIntervalMinutes: normalizeSubscriptionUpdateInterval(group.updateIntervalMinutes)
    };
  }

  private static normalizeNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
    const normalized = new Array<ProxyNode>();
    const idCounts = new Map<string, number>();
    for (let index = 0; index < nodes.length; index++) {
      const node = nodes[index];
      const id = SubscriptionStore.uniqueNodeId(node.id ?? '', index, idCounts);
      const configType = SubscriptionStore.normalizeNodeConfigType(node);
      const protocol = node.protocol ?? '';
      normalized.push({
        id,
        name: node.name ?? '',
        protocol: protocol.length > 0 ? protocol : SubscriptionStore.protocolForConfigType(configType, ''),
        outboundJson: node.outboundJson ?? '',
        configType,
        sourceUrl: node.sourceUrl ?? '',
        rawLink: node.rawLink ?? '',
        updatedAt: node.updatedAt ?? 0,
        delayMs: node.delayMs ?? -1,
        delayTestAt: node.delayTestAt ?? 0,
        delayStatus: node.delayStatus ?? ''
      });
    }
    return normalized;
  }

  private static uniqueNodeId(rawId: string, index: number, idCounts: Map<string, number>): string {
    const baseId = rawId.length > 0 ? rawId : `node-${index}`;
    const count = idCounts.get(baseId) ?? 0;
    idCounts.set(baseId, count + 1);
    if (count === 0) {
      return baseId;
    }
    return `${baseId}-${count + 1}`;
  }

  private static mergeNodeRuntime(existing: Array<ProxyNode>, next: Array<ProxyNode>): Array<ProxyNode> {
    const merged = new Array<ProxyNode>();
    for (let index = 0; index < next.length; index++) {
      const node = next[index];
      const previous = SubscriptionStore.findNode(existing, node.id);
      if (previous !== null) {
        node.delayMs = previous.delayMs;
        node.delayStatus = previous.delayStatus;
        node.delayTestAt = previous.delayTestAt;
      }
      merged.push(node);
    }
    return merged;
  }

  public static activeGroup(profile: SubscriptionProfile): SubscriptionGroup | null {
    return SubscriptionStore.findGroup(profile.groups, profile.selectedGroupId);
  }

  private static findGroup(groups: Array<SubscriptionGroup>, groupId: string): SubscriptionGroup | null {
    for (let index = 0; index < groups.length; index++) {
      if (groups[index].id === groupId) {
        return groups[index];
      }
    }
    return null;
  }

  public static findGroupByUrl(groups: Array<SubscriptionGroup>, url: string): SubscriptionGroup | null {
    for (let index = 0; index < groups.length; index++) {
      if (groups[index].url === url) {
        return groups[index];
      }
    }
    return null;
  }

  private static findNode(nodes: Array<ProxyNode>, nodeId: string): ProxyNode | null {
    for (let index = 0; index < nodes.length; index++) {
      if (nodes[index].id === nodeId) {
        return nodes[index];
      }
    }
    return null;
  }

  private static resolveSelectedNodeId(nodes: Array<ProxyNode>, selectedNodeId: string): string {
    if (SubscriptionStore.findNode(nodes, selectedNodeId) !== null) {
      return selectedNodeId;
    }
    return nodes.length > 0 ? nodes[0].id : '';
  }

  private static dedupeNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
    return dedupeProxyNodes(nodes);
  }

  private static createGroup(
    url: string,
    name: string,
    userAgent: string = '',
    filter: string = '',
    prevProfile: string = '',
    nextProfile: string = '',
    allowInsecureUrl: boolean = false,
    autoUpdate: boolean = false,
    updateIntervalMinutes: number = DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
  ): SubscriptionGroup {
    const seed = `${url}-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    return {
      id: SubscriptionStore.makeGroupId(seed),
      name,
      url,
      enabled: true,
      selectedNodeId: '',
      nodes: [],
      updatedAt: 0,
      userAgent,
      filter,
      prevProfile,
      nextProfile,
      allowInsecureUrl,
      autoUpdate,
      updateIntervalMinutes: normalizeSubscriptionUpdateInterval(updateIntervalMinutes)
    };
  }

  private static createEmpty(): SubscriptionProfile {
    return {
      url: '',
      selectedNodeId: '',
      nodes: [],
      updatedAt: 0,
      selectedGroupId: '',
      groups: []
    };
  }

  private static nameFromUrl(url: string): string {
    if (url.length === 0) {
      return 'Subscription';
    }
    const stripped = url.replace('https://', '').replace('http://', '');
    const slash = stripped.indexOf('/');
    return slash >= 0 ? stripped.substring(0, slash) : stripped;
  }

  private static makeGroupId(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash = (hash ^ value.charCodeAt(index)) * 16777619;
      hash = hash >>> 0;
    }
    return `sub-${hash.toString(16)}`;
  }

  private static normalizeNodeConfigType(node: ProxyNode): XrayConfigType {
    if (node.configType === 'full') {
      return 'full';
    }
    if (node.configType === 'proxy-chain') {
      return 'proxy-chain';
    }
    if (node.configType === 'policy-group') {
      return 'policy-group';
    }
    const validation = normalizeConfigInput(node.outboundJson ?? '');
    return validation.configType === 'full' || validation.configType === 'proxy-chain' || validation.configType === 'policy-group' ? validation.configType : 'outbound';
  }

  private static resolveConfigType(detected?: XrayConfigType, fallback?: XrayConfigType): XrayConfigType {
    if (detected === 'full') {
      return 'full';
    }
    if (detected === 'proxy-chain') {
      return 'proxy-chain';
    }
    if (detected === 'policy-group') {
      return 'policy-group';
    }
    if (detected === 'outbound') {
      return 'outbound';
    }
    if (fallback === 'full' || fallback === 'proxy-chain' || fallback === 'policy-group') {
      return fallback;
    }
    return 'outbound';
  }

  private static protocolForConfigType(configType: XrayConfigType, detectedProtocol: string): string {
    if (configType === 'full') {
      return 'custom';
    }
    if (configType === 'proxy-chain') {
      return 'proxy-chain';
    }
    if (configType === 'policy-group') {
      return 'policy-group';
    }
    return detectedProtocol;
  }
}
