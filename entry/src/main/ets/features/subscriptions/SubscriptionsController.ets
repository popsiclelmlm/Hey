import { common } from '@kit.AbilityKit';
import { translate } from '../../core/I18n';
import { AppLanguage, ProxyNode, SubscriptionGroup, SubscriptionProfile } from '../../core/Profile';
import { ProfileStore } from '../../storage/ProfileStore';
import { SubscriptionStore } from '../../storage/SubscriptionStore';
import { SubscriptionManager, SubscriptionUpdateResult } from '../../services/SubscriptionManager';
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

export class SubscriptionsController {
  async load(context: common.Context, language: AppLanguage): Promise<SubscriptionsControllerState> {
    return this.buildState(await SubscriptionStore.load(context), language, '');
  }

  async saveGroup(context: common.Context, urlValue: string, language: AppLanguage): Promise<SubscriptionsControllerState> {
    const url = urlValue.trim();
    if (url.length === 0) {
      return this.buildState(await SubscriptionStore.load(context), language, translate(language, 'error.emptySubscriptionUrl'));
    }
    try {
      const subscription = await SubscriptionStore.saveUrl(context, url);
      return this.buildState(subscription, language, translate(language, 'log.subscriptionGroupSaved'));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.saveSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async update(context: common.Context, urlValue: string, selectedNodeId: string, language: AppLanguage): Promise<SubscriptionsControllerState> {
    const url = urlValue.trim();
    if (url.length === 0) {
      return this.buildState(await SubscriptionStore.load(context), language, translate(language, 'error.emptySubscriptionUrl'));
    }

    try {
      await SubscriptionStore.saveUrl(context, url);
      const result: SubscriptionUpdateResult = await SubscriptionManager.fetchAndParse(url);
      if (!result.ok) {
        return this.buildState(await SubscriptionStore.load(context), language, localizeCoreMessage(language, result.message));
      }

      let nextSelectedId = selectedNodeId;
      if (this.findNode(result.nodes, nextSelectedId) === null) {
        nextSelectedId = result.nodes[0].id;
      }
      const subscription = await SubscriptionStore.saveNodes(context, url, result.nodes, nextSelectedId);
      const selected = this.findNode(subscription.nodes, nextSelectedId);
      if (selected !== null) {
        await ProfileStore.save(context, selected.outboundJson);
      }
      return this.buildState(subscription, language, localizeCoreMessage(language, result.message));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.updateSubscription', 'error', this.stringifyError(error)));
    }
  }

  async selectGroup(context: common.Context, group: SubscriptionGroup, language: AppLanguage): Promise<SubscriptionsControllerState> {
    try {
      const subscription = await SubscriptionStore.selectGroup(context, group.id);
      const selected = this.findNode(subscription.nodes, subscription.selectedNodeId);
      if (selected !== null) {
        await ProfileStore.save(context, selected.outboundJson);
      }
      return this.buildState(subscription, language, formatOne(language, 'log.openedSubscriptionGroup', 'name', group.name));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.selectSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async toggleGroup(context: common.Context, group: SubscriptionGroup, language: AppLanguage): Promise<SubscriptionsControllerState> {
    try {
      const subscription = await SubscriptionStore.toggleGroup(context, group.id);
      const status = group.enabled ? translate(language, 'common.disabled') : translate(language, 'common.enabled');
      return this.buildState(subscription, language, formatTwo(language, 'log.subscriptionGroupToggled', 'name', group.name, 'status', status));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.toggleSubscriptionGroup', 'error', this.stringifyError(error)));
    }
  }

  async removeGroup(context: common.Context, group: SubscriptionGroup, language: AppLanguage): Promise<SubscriptionsControllerState> {
    try {
      const subscription = await SubscriptionStore.removeGroup(context, group.id);
      return this.buildState(subscription, language, formatOne(language, 'log.removedSubscriptionGroup', 'name', group.name));
    } catch (error) {
      return this.buildState(await SubscriptionStore.load(context), language, formatOne(language, 'error.removeSubscriptionGroup', 'error', this.stringifyError(error)));
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
