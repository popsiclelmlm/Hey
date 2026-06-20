import { ProxyNode, SubscriptionGroup } from './Profile';

export const DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES: number = 1440;
export const MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES: number = 15;

export function moveSubscriptionGroup(groups: Array<SubscriptionGroup>, groupId: string, delta: number): Array<SubscriptionGroup> {
  const next = copySubscriptionGroups(groups);
  const fromIndex = findSubscriptionGroupIndex(next, groupId);
  const toIndex = fromIndex + delta;
  if (fromIndex < 0 || toIndex < 0 || toIndex >= next.length) {
    return next;
  }

  const current = next[fromIndex];
  next[fromIndex] = next[toIndex];
  next[toIndex] = current;
  return next;
}

export function normalizeSubscriptionUpdateInterval(value: number | undefined): number {
  if (value === undefined || Number.isNaN(value) || Math.floor(value) !== value || value <= 0) {
    return DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES;
  }
  return Math.max(MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES, value);
}

export function isSubscriptionAutoUpdateDue(group: SubscriptionGroup, now: number): boolean {
  if (!group.enabled || !group.autoUpdate || group.url.trim().length === 0) {
    return false;
  }

  const intervalMinutes = normalizeSubscriptionUpdateInterval(group.updateIntervalMinutes);
  const intervalMs = intervalMinutes * 60 * 1000;
  if (group.updatedAt <= 0) {
    return true;
  }
  return now - group.updatedAt >= intervalMs;
}

function findSubscriptionGroupIndex(groups: Array<SubscriptionGroup>, groupId: string): number {
  for (let index = 0; index < groups.length; index++) {
    if (groups[index].id === groupId) {
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
    nodes: copyProxyNodes(group.nodes),
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

function copyProxyNodes(nodes: Array<ProxyNode>): Array<ProxyNode> {
  const copied = new Array<ProxyNode>();
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes[index];
    copied.push({
      id: node.id,
      name: node.name,
      protocol: node.protocol,
      outboundJson: node.outboundJson,
      configType: node.configType,
      sourceUrl: node.sourceUrl,
      rawLink: node.rawLink,
      updatedAt: node.updatedAt,
      delayMs: node.delayMs,
      delayTestAt: node.delayTestAt,
      delayStatus: node.delayStatus
    });
  }
  return copied;
}
