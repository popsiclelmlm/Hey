import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { workScheduler } from '@kit.BackgroundTasksKit';
import {
  SUBSCRIPTION_AUTO_UPDATE_WORK_ABILITY,
  SUBSCRIPTION_AUTO_UPDATE_WORK_BUNDLE_NAME,
  SUBSCRIPTION_AUTO_UPDATE_WORK_ID,
  SubscriptionAutoUpdateGroupSchedulePlan,
  SubscriptionAutoUpdateSchedulePlan,
  buildSubscriptionAutoUpdateSchedulePlan
} from '../core/SubscriptionSchedulerPlan';
import { SubscriptionStore } from '../storage/SubscriptionStore';

const PREFERENCES_NAME: string = 'hey_subscription_background_scheduler';
const SCHEDULED_WORKS_KEY: string = 'scheduled_works';

export interface SubscriptionBackgroundScheduleResult {
  scheduled: boolean;
  enabledGroupCount: number;
  repeatCycleTimeMs: number;
  message: string;
}

interface SubscriptionScheduledWorkRecord {
  groupId: string;
  workId: number;
}

export class SubscriptionBackgroundScheduler {
  static async sync(context: common.Context): Promise<SubscriptionBackgroundScheduleResult> {
    const profile = await SubscriptionStore.load(context);
    const plan = buildSubscriptionAutoUpdateSchedulePlan(profile.groups);
    if (!plan.enabled) {
      return SubscriptionBackgroundScheduler.cancel(context, 'No enabled subscription auto-update groups.');
    }

    try {
      const previous = await SubscriptionBackgroundScheduler.loadScheduledWorks(context);
      SubscriptionBackgroundScheduler.stopExistingWork(previous);
      for (let index = 0; index < plan.groupPlans.length; index++) {
        workScheduler.startWork(SubscriptionBackgroundScheduler.buildWorkInfo(plan.groupPlans[index], plan));
      }
      await SubscriptionBackgroundScheduler.saveScheduledWorks(context, plan.groupPlans);
      return {
        scheduled: true,
        enabledGroupCount: plan.enabledGroupCount,
        repeatCycleTimeMs: plan.repeatCycleTimeMs,
        message: `Subscription background auto-update scheduled for ${plan.enabledGroupCount} group task(s).`
      };
    } catch (error) {
      return {
        scheduled: false,
        enabledGroupCount: plan.enabledGroupCount,
        repeatCycleTimeMs: plan.repeatCycleTimeMs,
        message: `Subscription background auto-update schedule failed: ${SubscriptionBackgroundScheduler.stringifyError(error)}`
      };
    }
  }

  static async cancel(context: common.Context, reason: string = 'Subscription background auto-update disabled.'): Promise<SubscriptionBackgroundScheduleResult> {
    try {
      const previous = await SubscriptionBackgroundScheduler.loadScheduledWorks(context);
      SubscriptionBackgroundScheduler.stopExistingWork(previous);
      await SubscriptionBackgroundScheduler.saveScheduledWorks(context, []);
    } catch (error) {
      return {
        scheduled: false,
        enabledGroupCount: 0,
        repeatCycleTimeMs: 0,
        message: `${reason} Stop request ignored: ${SubscriptionBackgroundScheduler.stringifyError(error)}`
      };
    }

    return {
      scheduled: false,
      enabledGroupCount: 0,
      repeatCycleTimeMs: 0,
      message: reason
    };
  }

  private static stopExistingWork(previous: Array<SubscriptionScheduledWorkRecord>): void {
    SubscriptionBackgroundScheduler.stopWorkId(SUBSCRIPTION_AUTO_UPDATE_WORK_ID);
    for (let index = 0; index < previous.length; index++) {
      SubscriptionBackgroundScheduler.stopWorkId(previous[index].workId);
    }
  }

  private static stopWorkId(workId: number): void {
    try {
      workScheduler.stopWork(SubscriptionBackgroundScheduler.buildCancelWorkInfo(workId), true);
    } catch (error) {
      // WorkScheduler throws when there is no existing work. Registering the new
      // work below is still the source of truth for schedule success.
    }
  }

  private static buildWorkInfo(groupPlan: SubscriptionAutoUpdateGroupSchedulePlan, plan: SubscriptionAutoUpdateSchedulePlan): workScheduler.WorkInfo {
    return {
      workId: groupPlan.workId,
      bundleName: SUBSCRIPTION_AUTO_UPDATE_WORK_BUNDLE_NAME,
      abilityName: SUBSCRIPTION_AUTO_UPDATE_WORK_ABILITY,
      isPersisted: true,
      networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      isRepeat: true,
      repeatCycleTime: groupPlan.repeatCycleTimeMs,
      parameters: {
        source: 'subscription-auto-update',
        groupId: groupPlan.groupId,
        workId: groupPlan.workId,
        enabledGroupCount: plan.enabledGroupCount,
        intervalMinutes: groupPlan.intervalMinutes,
        nextDelayTimeMs: groupPlan.nextDelayTimeMs
      }
    };
  }

  private static buildCancelWorkInfo(workId: number): workScheduler.WorkInfo {
    return {
      workId,
      bundleName: SUBSCRIPTION_AUTO_UPDATE_WORK_BUNDLE_NAME,
      abilityName: SUBSCRIPTION_AUTO_UPDATE_WORK_ABILITY
    };
  }

  private static async loadScheduledWorks(context: common.Context): Promise<Array<SubscriptionScheduledWorkRecord>> {
    try {
      const store = await preferences.getPreferences(context, PREFERENCES_NAME);
      const rawValue = await store.get(SCHEDULED_WORKS_KEY, '');
      return SubscriptionBackgroundScheduler.parseScheduledWorks(rawValue.toString());
    } catch (error) {
      return [];
    }
  }

  private static async saveScheduledWorks(context: common.Context, groupPlans: Array<SubscriptionAutoUpdateGroupSchedulePlan>): Promise<void> {
    const records = new Array<SubscriptionScheduledWorkRecord>();
    for (let index = 0; index < groupPlans.length; index++) {
      records.push({
        groupId: groupPlans[index].groupId,
        workId: groupPlans[index].workId
      });
    }
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    await store.put(SCHEDULED_WORKS_KEY, JSON.stringify(records));
    await store.flush();
  }

  private static parseScheduledWorks(raw: string): Array<SubscriptionScheduledWorkRecord> {
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Array<SubscriptionScheduledWorkRecord>;
      const records = new Array<SubscriptionScheduledWorkRecord>();
      for (let index = 0; index < parsed.length; index++) {
        const record = parsed[index];
        if (record.groupId.length > 0 && record.workId > 0) {
          records.push({
            groupId: record.groupId,
            workId: record.workId
          });
        }
      }
      return records;
    } catch (error) {
      return [];
    }
  }

  private static stringifyError(error: Error | Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
