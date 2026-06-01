import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ProxyNode, SubscriptionGroup, SubscriptionProfile } from '../core/Profile';

const PREFERENCES_NAME: string = 'hey_vpn_subscription';
const SUBSCRIPTION_KEY: string = 'subscription_profile';

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

  static async saveUrl(context: common.Context, url: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    let group = SubscriptionStore.activeGroup(profile);
    if (group === null) {
      group = SubscriptionStore.createGroup(url, SubscriptionStore.nameFromUrl(url));
      profile.groups.push(group);
      profile.selectedGroupId = group.id;
    }
    group.url = url;
    if (group.name.length === 0 || group.name.startsWith('Subscription ')) {
      group.name = SubscriptionStore.nameFromUrl(url);
    }
    group.updatedAt = Date.now();
    await SubscriptionStore.save(context, SubscriptionStore.normalize(profile));
    return SubscriptionStore.load(context);
  }

  static async saveNodes(context: common.Context, url: string, nodes: Array<ProxyNode>, selectedNodeId: string): Promise<SubscriptionProfile> {
    const profile = await SubscriptionStore.load(context);
    let group = SubscriptionStore.findGroupByUrl(profile.groups, url);
    if (group === null) {
      group = SubscriptionStore.activeGroup(profile);
    }
    if (group === null) {
      group = SubscriptionStore.createGroup(url, SubscriptionStore.nameFromUrl(url));
      profile.groups.push(group);
    }

    group.url = url;
    group.nodes = SubscriptionStore.mergeNodeRuntime(group.nodes, nodes);
    group.selectedNodeId = selectedNodeId;
    group.updatedAt = Date.now();
    profile.selectedGroupId = group.id;
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
      group.updatedAt = Date.now();
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
        updatedAt: profile.updatedAt
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
    return {
      id: group.id ?? SubscriptionStore.makeGroupId(`${url}-${index}`),
      name: group.name ?? SubscriptionStore.nameFromUrl(url),
      url,
      enabled: group.enabled ?? true,
      selectedNodeId: group.selectedNodeId ?? '',
      nodes: SubscriptionStore.normalizeNodes(group.nodes ?? []),
      updatedAt: group.updatedAt ?? 0
    };
  }

  private static normalizeNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
    const normalized = new Array<ProxyNode>();
    for (let index = 0; index < nodes.length; index++) {
      const node = nodes[index];
      normalized.push({
        id: node.id ?? '',
        name: node.name ?? '',
        protocol: node.protocol ?? '',
        outboundJson: node.outboundJson ?? '',
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

  private static activeGroup(profile: SubscriptionProfile): SubscriptionGroup | null {
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

  private static findGroupByUrl(groups: Array<SubscriptionGroup>, url: string): SubscriptionGroup | null {
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

  private static createGroup(url: string, name: string): SubscriptionGroup {
    return {
      id: SubscriptionStore.makeGroupId(url.length > 0 ? url : Date.now().toString()),
      name,
      url,
      enabled: true,
      selectedNodeId: '',
      nodes: [],
      updatedAt: 0
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
}
