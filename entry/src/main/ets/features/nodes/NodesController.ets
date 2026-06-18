import { common } from '@kit.AbilityKit';
import { AppLanguage, ProxyNode, ProxyProfile, SubscriptionGroup, SubscriptionProfile, ValidationResult } from '../../core/Profile';
import { normalizeOutboundInput } from '../../core/XrayConfig';
import { ProfileStore } from '../../storage/ProfileStore';
import { SubscriptionStore } from '../../storage/SubscriptionStore';
import { formatOne, localizedProfileSavedText, localizedSubscriptionStatusText, localizeCoreMessage } from '../../utils/LocalizationPresenter';

export interface NodesControllerState {
  outboundJson: string;
  validationOk: boolean;
  validationMessage: string;
  profileUpdatedAt: string;
  profileUpdatedAtValue: number;
  subscriptionUrl: string;
  nodes: Array<ProxyNode>;
  selectedNodeId: string;
  subscriptionMessage: string;
  subscriptionUpdatedAt: number;
  subscriptionGroups: Array<SubscriptionGroup>;
  selectedGroupId: string;
  lastError: string;
}

export interface SaveProfileResult {
  profile: ProxyProfile | null;
  outboundJson: string;
  validationOk: boolean;
  validationMessage: string;
  profileUpdatedAt: string;
  profileUpdatedAtValue: number;
  lastError: string;
}

export class NodesController {
  async load(context: common.Context, language: AppLanguage): Promise<NodesControllerState> {
    const profile = await ProfileStore.load(context);
    const subscription = await SubscriptionStore.load(context);
    let outboundJson = profile.outboundJson;
    const selected = this.findNodeInList(subscription.nodes, subscription.selectedNodeId);
    if (selected !== null) {
      outboundJson = selected.outboundJson;
    }
    const validation = this.validateConfig(outboundJson, language);
    return this.buildState(subscription, outboundJson, validation, profile.updatedAt, language, '');
  }

  validateConfig(outboundJson: string, language: AppLanguage): ValidationResult {
    const validation = normalizeOutboundInput(outboundJson);
    return {
      valid: validation.valid,
      message: localizeCoreMessage(language, validation.message),
      protocol: validation.protocol,
      normalizedJson: validation.normalizedJson
    };
  }

  async saveProfile(context: common.Context, outboundJson: string, language: AppLanguage): Promise<SaveProfileResult> {
    const validation = normalizeOutboundInput(outboundJson);
    const validationMessage = localizeCoreMessage(language, validation.message);
    if (!validation.valid) {
      return {
        profile: null,
        outboundJson,
        validationOk: false,
        validationMessage,
        profileUpdatedAt: localizedProfileSavedText(language, 0),
        profileUpdatedAtValue: 0,
        lastError: validationMessage
      };
    }

    try {
      const profile = await ProfileStore.save(context, validation.normalizedJson);
      return {
        profile,
        outboundJson: validation.normalizedJson,
        validationOk: true,
        validationMessage,
        profileUpdatedAt: localizedProfileSavedText(language, profile.updatedAt),
        profileUpdatedAtValue: profile.updatedAt,
        lastError: ''
      };
    } catch (error) {
      const message = formatOne(language, 'error.saveProfile', 'error', JSON.stringify(error));
      return {
        profile: null,
        outboundJson,
        validationOk: validation.valid,
        validationMessage,
        profileUpdatedAt: localizedProfileSavedText(language, 0),
        profileUpdatedAtValue: 0,
        lastError: message
      };
    }
  }

  async selectNode(context: common.Context, node: ProxyNode, language: AppLanguage): Promise<NodesControllerState> {
    try {
      const subscription = await SubscriptionStore.selectNode(context, node.id);
      const profile = await ProfileStore.save(context, node.outboundJson);
      const validation = this.validateConfig(node.outboundJson, language);
      return this.buildState(subscription, node.outboundJson, validation, profile.updatedAt, language, '');
    } catch (error) {
      const subscription = await SubscriptionStore.load(context);
      const validation = this.validateConfig(node.outboundJson, language);
      return this.buildState(subscription, node.outboundJson, validation, 0, language, formatOne(language, 'error.selectNode', 'error', JSON.stringify(error)));
    }
  }

  async removeNode(context: common.Context, nodeId: string, language: AppLanguage): Promise<NodesControllerState> {
    const subscription = await SubscriptionStore.removeNode(context, nodeId);
    return this.stateFromSubscription(context, subscription, language, '');
  }

  async dedupeActiveGroupNodes(context: common.Context, language: AppLanguage): Promise<NodesControllerState> {
    const subscription = await SubscriptionStore.dedupeActiveGroupNodes(context);
    return this.stateFromSubscription(context, subscription, language, '');
  }

  async removeInvalidNodes(context: common.Context, language: AppLanguage): Promise<NodesControllerState> {
    const subscription = await SubscriptionStore.removeInvalidNodes(context);
    return this.stateFromSubscription(context, subscription, language, '');
  }

  async clearActiveGroupNodes(context: common.Context, language: AppLanguage): Promise<NodesControllerState> {
    const subscription = await SubscriptionStore.clearActiveGroupNodes(context);
    return this.stateFromSubscription(context, subscription, language, '');
  }

  findNode(nodes: Array<ProxyNode>, nodeId: string): ProxyNode | null {
    return this.findNodeInList(nodes, nodeId);
  }

  private async stateFromSubscription(context: common.Context, subscription: SubscriptionProfile, language: AppLanguage, lastError: string): Promise<NodesControllerState> {
    const profile = await ProfileStore.load(context);
    const selected = this.findNodeInList(subscription.nodes, subscription.selectedNodeId);
    const outboundJson = selected !== null ? selected.outboundJson : profile.outboundJson;
    const validation = this.validateConfig(outboundJson, language);
    return this.buildState(subscription, outboundJson, validation, profile.updatedAt, language, lastError);
  }

  private buildState(subscription: SubscriptionProfile, outboundJson: string, validation: ValidationResult, profileUpdatedAtValue: number, language: AppLanguage, lastError: string): NodesControllerState {
    return {
      outboundJson,
      validationOk: validation.valid,
      validationMessage: validation.message,
      profileUpdatedAt: localizedProfileSavedText(language, profileUpdatedAtValue),
      profileUpdatedAtValue,
      subscriptionUrl: subscription.url,
      nodes: subscription.nodes,
      selectedNodeId: subscription.selectedNodeId,
      subscriptionMessage: localizedSubscriptionStatusText(language, subscription.updatedAt),
      subscriptionUpdatedAt: subscription.updatedAt,
      subscriptionGroups: subscription.groups,
      selectedGroupId: subscription.selectedGroupId,
      lastError
    };
  }

  private findNodeInList(nodes: Array<ProxyNode>, nodeId: string): ProxyNode | null {
    for (let index = 0; index < nodes.length; index++) {
      if (nodes[index].id === nodeId) {
        return nodes[index];
      }
    }
    return null;
  }
}

export const NODES_CONTROLLER: NodesController = new NodesController();
