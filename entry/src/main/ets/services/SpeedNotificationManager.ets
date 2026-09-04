import { common, wantAgent, WantAgent, Want } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { AppLanguage, ConnectionStatus, RuntimeStats } from '../core/Profile';
import {
  buildSpeedNotificationAdditionalText,
  buildSpeedNotificationText,
  calculateSpeedNotificationRates,
  sampleSpeedNotificationStats,
  shouldPublishSpeedNotification,
  SpeedNotificationSample
} from '../core/SpeedNotification';
import { translate } from '../core/I18n';
import { DiagnosticLog } from './DiagnosticLog';

const SPEED_NOTIFICATION_ID: number = 42001;
const SPEED_NOTIFICATION_LABEL: string = 'hey-speed';
// 点击速度通知拉起主界面用（bundleName 见 AppScope/app.json5，abilityName 见 module.json5）。
const APP_BUNDLE_NAME: string = 'com.lmlm.hey';
const MAIN_ABILITY_NAME: string = 'EntryAbility';

export class SpeedNotificationManager {
  private published: boolean = false;
  private notificationMayBeVisible: boolean = true;
  private permissionRequested: boolean = false;
  private slotReady: boolean = false;
  private publishing: boolean = false;
  private lastPublishAt: number = 0;
  private lastSample: SpeedNotificationSample | null = null;
  private tapWantAgent: WantAgent | null = null;

  // 构建「点击通知拉起 Hey 主界面」的 WantAgent；首次构建后缓存复用。
  // 失败返回 null（不影响通知本身发布，只是点击不跳转）。
  private async ensureTapWantAgent(): Promise<WantAgent | null> {
    if (this.tapWantAgent !== null) {
      return this.tapWantAgent;
    }
    try {
      const want: Want = {
        bundleName: APP_BUNDLE_NAME,
        abilityName: MAIN_ABILITY_NAME
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: SPEED_NOTIFICATION_ID,
        // 已存在则更新、不重复创建，保证点击总是拉起当前实例。
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      this.tapWantAgent = await wantAgent.getWantAgent(info);
    } catch (error) {
      this.tapWantAgent = null;
    }
    return this.tapWantAgent;
  }

  async sync(
    context: common.Context,
    status: ConnectionStatus,
    speedEnabled: boolean,
    stats: RuntimeStats,
    elapsedText: string,
    language: AppLanguage
  ): Promise<void> {
    if (status !== ConnectionStatus.RUNNING || !speedEnabled) {
      this.lastSample = null;
      await this.cancel(context);
      return;
    }

    const now = Date.now();
    const currentSample = sampleSpeedNotificationStats(stats, now);
    const rates = calculateSpeedNotificationRates(this.lastSample, currentSample);
    this.lastSample = currentSample;
    if (!shouldPublishSpeedNotification(now, this.lastPublishAt, this.published)) {
      return;
    }

    const text = buildSpeedNotificationText(language, rates);
    const additionalText = buildSpeedNotificationAdditionalText(language, stats, elapsedText);
    await this.publish(context, language, text, additionalText, now);
  }

  async cancel(context: common.Context): Promise<void> {
    if (!this.notificationMayBeVisible) {
      return;
    }
    try {
      await notificationManager.cancel(SPEED_NOTIFICATION_ID, SPEED_NOTIFICATION_LABEL);
    } catch (error) {
      // Missing notification is expected after process restarts or first launch.
    }
    this.published = false;
    this.notificationMayBeVisible = false;
    this.lastPublishAt = 0;
  }

  private async publish(
    context: common.Context,
    language: AppLanguage,
    text: string,
    additionalText: string,
    now: number
  ): Promise<void> {
    if (this.publishing) {
      return;
    }
    this.publishing = true;
    try {
      if (!await this.ensureEnabled(context)) {
        return;
      }
      await this.ensureSlot();
      const tapAgent = await this.ensureTapWantAgent();
      const request: notificationManager.NotificationRequest = {
        id: SPEED_NOTIFICATION_ID,
        label: SPEED_NOTIFICATION_LABEL,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        tapDismissed: false,
        isAlertOnce: true,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: translate(language, 'notification.speed.title'),
            text,
            additionalText
          }
        }
      };
      // 点击常驻速度通知即拉起 Hey 主界面（issue #16）：后台被中断时重连、用完关都更方便。
      if (tapAgent !== null) {
        request.wantAgent = tapAgent;
      }
      await notificationManager.publish(request);
      this.published = true;
      this.notificationMayBeVisible = true;
      this.lastPublishAt = now;
    } catch (error) {
      this.appendDiagnostic(context, 'Speed notification publish failed.', error);
    } finally {
      this.publishing = false;
    }
  }

  private async ensureEnabled(context: common.Context): Promise<boolean> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return true;
      }
      if (this.permissionRequested) {
        return false;
      }
      this.permissionRequested = true;
      await notificationManager.requestEnableNotification(context as common.UIAbilityContext);
      return notificationManager.isNotificationEnabled();
    } catch (error) {
      this.appendDiagnostic(context, 'Speed notification permission unavailable.', error);
      return false;
    }
  }

  private async ensureSlot(): Promise<void> {
    if (this.slotReady) {
      return;
    }
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (error) {
      // Publishing will still report a diagnostic if the slot state blocks it.
    }
    this.slotReady = true;
  }

  private appendDiagnostic(context: common.Context, message: string, error: Object): void {
    DiagnosticLog.append(context, {
      at: Date.now(),
      level: 'warn',
      source: 'notification',
      message,
      details: JSON.stringify(error)
    });
  }
}

export const SPEED_NOTIFICATION_MANAGER: SpeedNotificationManager = new SpeedNotificationManager();
