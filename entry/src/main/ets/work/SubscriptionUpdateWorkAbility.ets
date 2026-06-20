import { common } from '@kit.AbilityKit';
import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SUBSCRIPTIONS_CONTROLLER } from '../features/subscriptions/SubscriptionsController';
import { DiagnosticLog } from '../services/DiagnosticLog';
import { SubscriptionBackgroundScheduler } from '../services/SubscriptionBackgroundScheduler';

export default class SubscriptionUpdateWorkAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    this.runSubscriptionUpdate(work);
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    DiagnosticLog.append(this.context as common.Context, {
      at: Date.now(),
      level: 'info',
      source: 'subscription-work',
      message: 'Subscription background work stopped.',
      details: `workId=${work.workId}`
    });
  }

  private async runSubscriptionUpdate(work: workScheduler.WorkInfo): Promise<void> {
    const context = this.context as common.Context;
    try {
      const settings = await SETTINGS_CONTROLLER.load(context);
      const groupId = this.workGroupId(work);
      const result = groupId.length > 0
        ? await SUBSCRIPTIONS_CONTROLLER.updateDueGroup(context, groupId, settings.language, Date.now(), 0)
        : await SUBSCRIPTIONS_CONTROLLER.updateDue(context, settings.language, Date.now(), 0);
      const schedule = await SubscriptionBackgroundScheduler.sync(context);
      DiagnosticLog.append(context, {
        at: Date.now(),
        level: result.failedCount > 0 ? 'warn' : 'info',
        source: 'subscription-work',
        message: `Subscription background update completed: ${result.updatedCount} success, ${result.failedCount} failed.`,
        details: `workId=${work.workId}; groupId=${groupId}; scheduled=${schedule.scheduled}; repeatCycleTimeMs=${schedule.repeatCycleTimeMs}`
      });
    } catch (error) {
      DiagnosticLog.append(context, {
        at: Date.now(),
        level: 'error',
        source: 'subscription-work',
        message: 'Subscription background update failed.',
        details: this.stringifyError(error)
      });
    }
  }

  private workGroupId(work: workScheduler.WorkInfo): string {
    const parameters = work.parameters;
    if (parameters === undefined) {
      return '';
    }
    const groupId = parameters['groupId'];
    return typeof groupId === 'string' ? groupId.trim() : '';
  }

  private stringifyError(error: Error | Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
