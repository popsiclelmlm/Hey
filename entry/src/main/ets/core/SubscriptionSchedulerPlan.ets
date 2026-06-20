import { SubscriptionGroup } from './Profile';
import { normalizeSubscriptionUpdateInterval } from './SubscriptionGroups';

export const SUBSCRIPTION_AUTO_UPDATE_WORK_ID: number = 260618;
export const SUBSCRIPTION_AUTO_UPDATE_WORK_ID_BASE: number = 261000;
const SUBSCRIPTION_AUTO_UPDATE_WORK_ID_SPACE: number = 900000;
export const SUBSCRIPTION_AUTO_UPDATE_WORK_BUNDLE_NAME: string = 'com.lmlm.hey';
export const SUBSCRIPTION_AUTO_UPDATE_WORK_ABILITY: string = 'SubscriptionUpdateWorkAbility';

export interface SubscriptionAutoUpdateGroupSchedulePlan {
  groupId: string;
  workId: number;
  intervalMinutes: number;
  repeatCycleTimeMs: number;
  nextDelayTimeMs: number;
}

export interface SubscriptionAutoUpdateSchedulePlan {
  enabled: boolean;
  enabledGroupCount: number;
  intervalMinutes: number;
  repeatCycleTimeMs: number;
  groupPlans: Array<SubscriptionAutoUpdateGroupSchedulePlan>;
}

export function buildSubscriptionAutoUpdateSchedulePlan(groups: Array<SubscriptionGroup>, now: number = Date.now()): SubscriptionAutoUpdateSchedulePlan {
  const groupPlans = buildSubscriptionAutoUpdateGroupSchedulePlans(groups, now);
  let enabledGroupCount = 0;
  let intervalMinutes = 0;

  for (let index = 0; index < groupPlans.length; index++) {
    const normalizedInterval = groupPlans[index].intervalMinutes;
    enabledGroupCount++;
    if (intervalMinutes === 0 || normalizedInterval < intervalMinutes) {
      intervalMinutes = normalizedInterval;
    }
  }

  return {
    enabled: enabledGroupCount > 0,
    enabledGroupCount,
    intervalMinutes,
    repeatCycleTimeMs: intervalMinutes > 0 ? intervalMinutes * 60 * 1000 : 0,
    groupPlans
  };
}

export function buildSubscriptionAutoUpdateGroupSchedulePlans(groups: Array<SubscriptionGroup>, now: number = Date.now()): Array<SubscriptionAutoUpdateGroupSchedulePlan> {
  const plans = new Array<SubscriptionAutoUpdateGroupSchedulePlan>();
  for (let index = 0; index < groups.length; index++) {
    const group = groups[index];
    if (!isSubscriptionAutoUpdateSchedulable(group)) {
      continue;
    }
    const intervalMinutes = normalizeSubscriptionUpdateInterval(group.updateIntervalMinutes);
    const repeatCycleTimeMs = intervalMinutes * 60 * 1000;
    plans.push({
      groupId: group.id,
      workId: subscriptionAutoUpdateWorkIdForGroup(group.id),
      intervalMinutes,
      repeatCycleTimeMs,
      nextDelayTimeMs: nextSubscriptionAutoUpdateDelayMs(group.updatedAt, repeatCycleTimeMs, now)
    });
  }
  return plans;
}

export function isSubscriptionAutoUpdateSchedulable(group: SubscriptionGroup): boolean {
  return group.enabled && (group.autoUpdate ?? false) && group.url.trim().length > 0;
}

export function subscriptionAutoUpdateWorkIdForGroup(groupId: string): number {
  let hash = 0;
  for (let index = 0; index < groupId.length; index++) {
    hash = (hash * 31 + groupId.charCodeAt(index)) % SUBSCRIPTION_AUTO_UPDATE_WORK_ID_SPACE;
  }
  return SUBSCRIPTION_AUTO_UPDATE_WORK_ID_BASE + hash;
}

function nextSubscriptionAutoUpdateDelayMs(updatedAt: number, repeatCycleTimeMs: number, now: number): number {
  if (updatedAt <= 0 || repeatCycleTimeMs <= 0) {
    return 0;
  }
  const nextDueAt = updatedAt + repeatCycleTimeMs;
  return nextDueAt > now ? nextDueAt - now : 0;
}
