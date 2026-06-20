import { common } from '@kit.AbilityKit';
import { translate } from '../../core/I18n';
import { AppLanguage, ProxyNode, SubscriptionGroup, SubscriptionProfile } from '../../core/Profile';
import {
  DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  isSubscriptionAutoUpdateDue,
  normalizeSubscriptionUpdateInterval
} from '../../core/SubscriptionGroups';
import { ProfileStore } from '../../storage/ProfileStore';
import { SubscriptionStore } from '../../storage/SubscriptionStore';
import { SubscriptionManager, SubscriptionUpdateResult } from '../../services/SubscriptionManager';
import { SubscriptionBackgroundScheduler } from '../../services/SubscriptionBackgroundScheduler';
import { formatOne, formatTwo, localizedSubscriptionStatusText, localizeCoreMessage } from '../../utils/LocalizationPresenter';

export interface SubscriptionsControllerState {
  subscriptionUrl: string;
  nodes: Array<ProxyNode>;
  selectedNodeId: string;
  subscriptionMessage: string;
  subscriptionUpdatedAt: number;
  subscriptionGroups: Array<SubscriptionGroup>;
  selectedGroupId: string;
}

export interface SubscriptionAutoUpdateResult {
  state: SubscriptionsControllerState;
  updatedCount: number;
  failedCount: number;
}

interface SubscriptionGroupUpdateResult {
  subscription: SubscriptionProfile;
  ok: boolean;
}

export class SubscriptionsController {
  async load(context: common.Context, language: AppLanguage): Promise<SubscriptionsControllerState> {
    return this.buildState(await SubscriptionStore.load(context), language, '');
  }

  async saveGroup(context: common.Context, urlValue: string, language: AppLanguage): Promise<SubscriptionsControllerState> {
    const url = urlValue.trim();
    if (url.length === 0) {
      return this.buildState(await SubscriptionStore.load(context), language, translate(language, 'error.emptySubscriptionUrl'));
    }
    const validationMessage = SubscriptionManager.validateSubscriptionUrl(url, false);
    if (validationMessage.length > 0) {
      return this.buildState(await SubscriptionStore.load(context), language, localizeCoreMessage(language, validationMessage));
    }
    try {
      const subscription = await SubscriptionStore.saveUrl(context, url);
      return this.buildState(subscription, language, translate(language, 'log.subscriptionGroupSaved'));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.saveSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async update(context: common.Context, groupId: string, urlValue: string, selectedNodeId: string, language: AppLanguage, proxyPort: number = 0): Promise<SubscriptionsControllerState> {
    if (groupId === 'sub-local') {
      return this.buildState(await SubscriptionStore.load(context), language, '本地节点分组无需更新');
    }
    const url = urlValue.trim();
    if (url.length === 0) {
      return this.buildState(await SubscriptionStore.load(context), language, translate(language, 'error.emptySubscriptionUrl'));
    }

    try {
      const profileBeforeUpdate = await SubscriptionStore.load(context);
      let targetGroupId = groupId.trim();
      if (targetGroupId.length === 0) {
        const active = SubscriptionStore.activeGroup(profileBeforeUpdate);
        if (active !== null && active.url === url) {
          targetGroupId = active.id;
        } else {
          const matched = SubscriptionStore.findGroupByUrl(profileBeforeUpdate.groups, url);
          if (matched !== null) {
            targetGroupId = matched.id;
          } else if (active !== null) {
            targetGroupId = active.id;
          }
        }
      }
      const allowInsecureUrl = this.findGroupAllowInsecureUrl(profileBeforeUpdate.groups, targetGroupId);
      const validationMessage = SubscriptionManager.validateSubscriptionUrl(url, allowInsecureUrl);
      if (validationMessage.length > 0) {
        return this.buildState(profileBeforeUpdate, language, localizeCoreMessage(language, validationMessage));
      }

      const subscriptionBeforeUpdate = await SubscriptionStore.saveUrl(context, url, targetGroupId, false);
      if (targetGroupId.length === 0) {
        targetGroupId = subscriptionBeforeUpdate.selectedGroupId;
      }

      const userAgent = this.findGroupUserAgent(subscriptionBeforeUpdate.groups, targetGroupId);
      const result: SubscriptionUpdateResult = await SubscriptionManager.fetchAndParse(url, userAgent, allowInsecureUrl, proxyPort);
      if (!result.ok) {
        return this.buildState(await SubscriptionStore.load(context), language, localizeCoreMessage(language, result.message));
      }

      const filter = this.findGroupFilter(subscriptionBeforeUpdate.groups, targetGroupId);
      const nodes = this.applyNodeFilter(result.nodes, filter);

      const subscription = await SubscriptionStore.saveNodes(context, targetGroupId, url, nodes, selectedNodeId);
      const selected = this.findNode(subscription.nodes, subscription.selectedNodeId);
      if (selected !== null) {
        await ProfileStore.save(context, selected.outboundJson, selected.configType);
      }
      return this.buildState(subscription, language, localizeCoreMessage(language, result.message));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.updateSubscription', 'error', this.stringifyError(error)));
    }
  }

  async addGroup(
    context: common.Context,
    name: string,
    url: string,
    userAgent: string,
    filter: string,
    prevProfile: string,
    nextProfile: string,
    allowInsecureUrl: boolean,
    language: AppLanguage,
    autoUpdate: boolean = false,
    updateIntervalMinutes: number = DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
  ): Promise<SubscriptionsControllerState> {
    const trimmedName = name.trim();
    const trimmedUrl = url.trim();
    if (trimmedName.length === 0) {
      return this.buildState(await SubscriptionStore.load(context), language, '订阅名称不能为空');
    }
    const validationMessage = this.validateEditableSubscriptionUrl(trimmedUrl, allowInsecureUrl, language);
    if (validationMessage.length > 0) {
      return this.buildState(await SubscriptionStore.load(context), language, validationMessage);
    }
    try {
      const normalizedInterval = normalizeSubscriptionUpdateInterval(updateIntervalMinutes);
      const subscription = await SubscriptionStore.addGroup(context, trimmedName, trimmedUrl, userAgent.trim(), filter.trim(), prevProfile.trim(), nextProfile.trim(), allowInsecureUrl, autoUpdate, normalizedInterval);
      await this.syncBackgroundSchedule(context);
      return this.buildState(subscription, language, translate(language, 'log.subscriptionGroupSaved'));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.saveSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async updateGroup(
    context: common.Context,
    groupId: string,
    name: string,
    url: string,
    userAgent: string,
    filter: string,
    prevProfile: string,
    nextProfile: string,
    allowInsecureUrl: boolean,
    language: AppLanguage,
    autoUpdate: boolean = false,
    updateIntervalMinutes: number = DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
  ): Promise<SubscriptionsControllerState> {
    const trimmedName = name.trim();
    const trimmedUrl = url.trim();
    if (trimmedName.length === 0) {
      return this.buildState(await SubscriptionStore.load(context), language, '订阅名称不能为空');
    }
    const validationMessage = this.validateEditableSubscriptionUrl(trimmedUrl, allowInsecureUrl, language);
    if (validationMessage.length > 0) {
      return this.buildState(await SubscriptionStore.load(context), language, validationMessage);
    }
    try {
      const normalizedInterval = normalizeSubscriptionUpdateInterval(updateIntervalMinutes);
      const subscription = await SubscriptionStore.updateGroup(context, groupId, trimmedName, trimmedUrl, userAgent.trim(), filter.trim(), prevProfile.trim(), nextProfile.trim(), allowInsecureUrl, autoUpdate, normalizedInterval);
      await this.syncBackgroundSchedule(context);
      return this.buildState(subscription, language, translate(language, 'log.subscriptionGroupSaved'));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.saveSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async updateAll(context: common.Context, language: AppLanguage, proxyPort: number = 0): Promise<SubscriptionsControllerState> {
    let subscription = await SubscriptionStore.load(context);
    let successCount = 0;
    let failedCount = 0;
    
    for (let index = 0; index < subscription.groups.length; index++) {
      const group = subscription.groups[index];
      const url = group.url.trim();
      if (url.length > 0 && group.enabled) {
        try {
          const result = await this.updateGroupNodes(context, group, false, proxyPort);
          subscription = result.subscription;
          if (result.ok) {
            successCount++;
          } else {
            failedCount++;
          }
        } catch (error) {
          failedCount++;
        }
      }
    }

    await this.syncBackgroundSchedule(context);
    
    const msg = failedCount === 0 
      ? `已成功更新 ${successCount} 个订阅分组` 
      : `更新完成: ${successCount} 个成功, ${failedCount} 个失败`;
    
    return this.buildState(subscription, language, msg);
  }

  async updateDue(context: common.Context, language: AppLanguage, now: number = Date.now(), proxyPort: number = 0): Promise<SubscriptionAutoUpdateResult> {
    let subscription = await SubscriptionStore.load(context);
    let updatedCount = 0;
    let failedCount = 0;

    for (let index = 0; index < subscription.groups.length; index++) {
      const group = subscription.groups[index];
      if (!isSubscriptionAutoUpdateDue(group, now)) {
        continue;
      }
      try {
        const result = await this.updateGroupNodes(context, group, false, proxyPort);
        subscription = result.subscription;
        if (result.ok) {
          updatedCount++;
        } else {
          failedCount++;
        }
      } catch (error) {
        failedCount++;
      }
    }

    await this.syncBackgroundSchedule(context);

    let message = '';
    if (updatedCount > 0 || failedCount > 0) {
      message = failedCount === 0
        ? `已自动更新 ${updatedCount} 个订阅分组`
        : `自动更新完成: ${updatedCount} 个成功, ${failedCount} 个失败`;
    }

    return {
      state: this.buildState(subscription, language, message),
      updatedCount,
      failedCount
    };
  }

  async updateDueGroup(context: common.Context, groupId: string, language: AppLanguage, now: number = Date.now(), proxyPort: number = 0): Promise<SubscriptionAutoUpdateResult> {
    let subscription = await SubscriptionStore.load(context);
    const group = this.findGroup(subscription.groups, groupId);
    if (group === null || !isSubscriptionAutoUpdateDue(group, now)) {
      return {
        state: this.buildState(subscription, language, ''),
        updatedCount: 0,
        failedCount: 0
      };
    }

    let updatedCount = 0;
    let failedCount = 0;
    try {
      const result = await this.updateGroupNodes(context, group, false, proxyPort);
      subscription = result.subscription;
      if (result.ok) {
        updatedCount++;
      } else {
        failedCount++;
      }
    } catch (error) {
      failedCount++;
    }

    await this.syncBackgroundSchedule(context);

    const message = failedCount === 0
      ? `已自动更新订阅分组：${group.name}`
      : `自动更新订阅分组失败：${group.name}`;

    return {
      state: this.buildState(subscription, language, message),
      updatedCount,
      failedCount
    };
  }

  async selectGroup(context: common.Context, group: SubscriptionGroup, language: AppLanguage): Promise<SubscriptionsControllerState> {
    try {
      const subscription = await SubscriptionStore.selectGroup(context, group.id);
      const selected = this.findNode(subscription.nodes, subscription.selectedNodeId);
      if (selected !== null) {
        await ProfileStore.save(context, selected.outboundJson, selected.configType);
      }
      return this.buildState(subscription, language, formatOne(language, 'log.openedSubscriptionGroup', 'name', group.name));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.selectSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async toggleGroup(context: common.Context, group: SubscriptionGroup, language: AppLanguage): Promise<SubscriptionsControllerState> {
    try {
      const subscription = await SubscriptionStore.toggleGroup(context, group.id);
      await this.syncBackgroundSchedule(context);
      const status = group.enabled ? translate(language, 'common.disabled') : translate(language, 'common.enabled');
      return this.buildState(subscription, language, formatTwo(language, 'log.subscriptionGroupToggled', 'name', group.name, 'status', status));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.toggleSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async removeGroup(context: common.Context, group: SubscriptionGroup, language: AppLanguage): Promise<SubscriptionsControllerState> {
    try {
      const subscription = await SubscriptionStore.removeGroup(context, group.id);
      await this.syncBackgroundSchedule(context);
      return this.buildState(subscription, language, formatOne(language, 'log.removedSubscriptionGroup', 'name', group.name));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.removeSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async moveGroup(context: common.Context, group: SubscriptionGroup, delta: number, language: AppLanguage): Promise<SubscriptionsControllerState> {
    try {
      const subscription = await SubscriptionStore.moveGroup(context, group.id, delta);
      return this.buildState(subscription, language, formatOne(language, 'log.subscriptionGroupReordered', 'name', group.name));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.moveSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  private buildState(subscription: SubscriptionProfile, language: AppLanguage, message: string): SubscriptionsControllerState {
    const state: SubscriptionsControllerState = {
      subscriptionUrl: subscription.url,
      nodes: subscription.nodes,
      selectedNodeId: subscription.selectedNodeId,
      subscriptionMessage: message.length > 0 ? message : localizedSubscriptionStatusText(language, subscription.updatedAt),
      subscriptionUpdatedAt: subscription.updatedAt,
      subscriptionGroups: subscription.groups,
      selectedGroupId: subscription.selectedGroupId
    };
    return state;
  }

  private findNode(nodes: Array<ProxyNode>, nodeId: string): ProxyNode | null {
    for (let index = 0; index < nodes.length; index++) {
      if (nodes[index].id === nodeId) {
        return nodes[index];
      }
    }
    return null;
  }

  private findGroup(groups: Array<SubscriptionGroup>, groupId: string): SubscriptionGroup | null {
    for (let index = 0; index < groups.length; index++) {
      if (groups[index].id === groupId) {
        return groups[index];
      }
    }
    return null;
  }

  private findGroupUserAgent(groups: Array<SubscriptionGroup>, groupId: string): string {
    for (let index = 0; index < groups.length; index++) {
      if (groups[index].id === groupId) {
        return groups[index].userAgent ?? '';
      }
    }
    return '';
  }

  private findGroupFilter(groups: Array<SubscriptionGroup>, groupId: string): string {
    for (let index = 0; index < groups.length; index++) {
      if (groups[index].id === groupId) {
        return groups[index].filter ?? '';
      }
    }
    return '';
  }

  private findGroupAllowInsecureUrl(groups: Array<SubscriptionGroup>, groupId: string): boolean {
    for (let index = 0; index < groups.length; index++) {
      if (groups[index].id === groupId) {
        return groups[index].allowInsecureUrl ?? false;
      }
    }
    return false;
  }

  private async updateGroupNodes(context: common.Context, group: SubscriptionGroup, makeActive: boolean, proxyPort: number): Promise<SubscriptionGroupUpdateResult> {
    const url = group.url.trim();
    const result = await SubscriptionManager.fetchAndParse(url, group.userAgent ?? '', group.allowInsecureUrl ?? false, proxyPort);
    if (!result.ok) {
      return {
        subscription: await SubscriptionStore.load(context),
        ok: false
      };
    }

    const nodes = this.applyNodeFilter(result.nodes, group.filter ?? '');
    return {
      subscription: await SubscriptionStore.saveNodes(context, group.id, url, nodes, group.selectedNodeId, makeActive),
      ok: true
    };
  }

  private validateEditableSubscriptionUrl(url: string, allowInsecureUrl: boolean, language: AppLanguage): string {
    if (url.length === 0) {
      return '';
    }
    const validationMessage = SubscriptionManager.validateSubscriptionUrl(url, allowInsecureUrl);
    return validationMessage.length > 0 ? localizeCoreMessage(language, validationMessage) : '';
  }

  private async syncBackgroundSchedule(context: common.Context): Promise<void> {
    try {
      await SubscriptionBackgroundScheduler.sync(context);
    } catch (error) {
      console.error(`Subscription background schedule sync failed: ${JSON.stringify(error)}`);
    }
  }

  // Keeps only nodes whose name matches the group's filter regex. An empty
  // filter, an invalid regex, or a pattern that matches nothing all fall back to
  // the full node list so a subscription is never silently emptied.
  private applyNodeFilter(nodes: Array<ProxyNode>, filter: string): Array<ProxyNode> {
    const pattern = filter.trim();
    if (pattern.length === 0) {
      return nodes;
    }
    try {
      const regex = new RegExp(pattern);
      const result = new Array<ProxyNode>();
      for (let index = 0; index < nodes.length; index++) {
        if (regex.test(nodes[index].name)) {
          result.push(nodes[index]);
        }
      }
      return result.length > 0 ? result : nodes;
    } catch (error) {
      return nodes;
    }
  }

  private stringifyError(error: Error): string {
    if (error.message.length > 0) {
      return error.message;
    }
    if (error.name.length > 0) {
      return error.name;
    }
    return `${error}`;
  }
}

export const SUBSCRIPTIONS_CONTROLLER: SubscriptionsController = new SubscriptionsController();
