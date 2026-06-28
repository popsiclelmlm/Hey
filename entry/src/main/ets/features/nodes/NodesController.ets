import { common } from '@kit.AbilityKit';
import { translate } from '../../core/I18n';
import { AppLanguage, ProxyNode, ProxyProfile, SubscriptionGroup, SubscriptionProfile, ValidationResult, XrayConfigType } from '../../core/Profile';
import { normalizeConfigInput } from '../../core/XrayConfig';
import { ProfileStore } from '../../storage/ProfileStore';
import { SubscriptionStore } from '../../storage/SubscriptionStore';
import { formatOne, localizedProfileSavedText, localizedSubscriptionStatusText, localizeCoreMessage } from '../../utils/LocalizationPresenter';

export interface NodesControllerState {
  outboundJson: string;
  configType: XrayConfigType;
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
  configType: XrayConfigType;
  validationOk: boolean;
  validationMessage: string;
  profileUpdatedAt: string;
  profileUpdatedAtValue: number;
  lastError: string;
}

export interface UpdateManualNodeResult {
  success: boolean;
  message: string;
  node: ProxyNode | null;
  selected: boolean;
  lastError: string;
}

export class NodesController {
  async load(context: common.Context, language: AppLanguage): Promise<NodesControllerState> {
    const profile = await ProfileStore.load(context);
    const subscription = await SubscriptionStore.load(context);
    let outboundJson = profile.outboundJson;
    let configType: XrayConfigType = profile.configType ?? 'outbound';
    // 当前节点是全局值，可能不在当前浏览的活动组里 —— 跨所有组查找它的 outbound。
    const selected = this.findNodeInGroups(subscription.groups, subscription.selectedNodeId);
    if (selected !== null) {
      outboundJson = selected.outboundJson;
      configType = selected.configType ?? 'outbound';
    }
    const validation = this.validateConfig(outboundJson, language, configType);
    return this.buildState(subscription, outboundJson, this.resolveConfigType(validation, configType), validation, profile.updatedAt, language, '');
  }

  validateConfig(outboundJson: string, language: AppLanguage, configType?: XrayConfigType): ValidationResult {
    const validation = normalizeConfigInput(outboundJson, configType);
    return {
      valid: validation.valid,
      message: localizeCoreMessage(language, validation.message),
      protocol: validation.protocol,
      normalizedJson: validation.normalizedJson,
      configType: validation.configType
    };
  }

  async saveProfile(context: common.Context, outboundJson: string, language: AppLanguage, configType?: XrayConfigType): Promise<SaveProfileResult> {
    const validation = normalizeConfigInput(outboundJson, configType);
    const validationMessage = localizeCoreMessage(language, validation.message);
    const resolvedConfigType = this.resolveConfigType(validation, configType);
    if (!validation.valid) {
      return {
        profile: null,
        outboundJson,
        configType: resolvedConfigType,
        validationOk: false,
        validationMessage,
        profileUpdatedAt: localizedProfileSavedText(language, 0),
        profileUpdatedAtValue: 0,
        lastError: validationMessage
      };
    }

    try {
      const profile = await ProfileStore.save(context, validation.normalizedJson, resolvedConfigType);
      return {
        profile,
        outboundJson: validation.normalizedJson,
        configType: resolvedConfigType,
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
        configType: resolvedConfigType,
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
      const configType = node.configType ?? 'outbound';
      const profile = await ProfileStore.save(context, node.outboundJson, configType);
      const validation = this.validateConfig(node.outboundJson, language, configType);
      return this.buildState(subscription, node.outboundJson, this.resolveConfigType(validation, configType), validation, profile.updatedAt, language, '');
    } catch (error) {
      const subscription = await SubscriptionStore.load(context);
      const configType = node.configType ?? 'outbound';
      const validation = this.validateConfig(node.outboundJson, language, configType);
      return this.buildState(subscription, node.outboundJson, this.resolveConfigType(validation, configType), validation, 0, language, formatOne(language, 'error.selectNode', 'error', JSON.stringify(error)));
    }
  }

  async removeNode(context: common.Context, nodeId: string, language: AppLanguage): Promise<NodesControllerState> {
    const subscription = await SubscriptionStore.removeNode(context, nodeId);
    return this.stateFromSubscription(context, subscription, language, '');
  }

  async updateManualNode(context: common.Context, nodeId: string, name: string, outboundJson: string, language: AppLanguage, configType?: XrayConfigType): Promise<UpdateManualNodeResult> {
    const validation = normalizeConfigInput(outboundJson, configType);
    const message = localizeCoreMessage(language, validation.message);
    const resolvedConfigType = this.resolveConfigType(validation, configType);
    if (!validation.valid) {
      return {
        success: false,
        message,
        node: null,
        selected: false,
        lastError: message
      };
    }

    try {
      const result = await SubscriptionStore.updateManualNode(context, nodeId, name, validation.normalizedJson, resolvedConfigType);
      if (!result.updated || result.node === null) {
        const lastError = translate(language, 'error.editManualNodeUnsupported');
        return {
          success: false,
          message,
          node: null,
          selected: false,
          lastError
        };
      }
      if (result.selected) {
        await ProfileStore.save(context, result.node.outboundJson, result.node.configType ?? resolvedConfigType);
      }
      return {
        success: true,
        message,
        node: result.node,
        selected: result.selected,
        lastError: ''
      };
    } catch (error) {
      const lastError = formatOne(language, 'error.saveProfile', 'error', JSON.stringify(error));
      return {
        success: false,
        message,
        node: null,
        selected: false,
        lastError
      };
    }
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
    const selected = this.findNodeInGroups(subscription.groups, subscription.selectedNodeId);
    const outboundJson = selected !== null ? selected.outboundJson : profile.outboundJson;
    const configType = selected !== null ? (selected.configType ?? 'outbound') : (profile.configType ?? 'outbound');
    const validation = this.validateConfig(outboundJson, language, configType);
    return this.buildState(subscription, outboundJson, this.resolveConfigType(validation, configType), validation, profile.updatedAt, language, lastError);
  }

  private buildState(subscription: SubscriptionProfile, outboundJson: string, configType: XrayConfigType, validation: ValidationResult, profileUpdatedAtValue: number, language: AppLanguage, lastError: string): NodesControllerState {
    return {
      outboundJson,
      configType,
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

  private resolveConfigType(validation: ValidationResult, fallback?: XrayConfigType): XrayConfigType {
    if (validation.configType === 'full') {
      return 'full';
    }
    if (validation.configType === 'proxy-chain') {
      return 'proxy-chain';
    }
    if (validation.configType === 'policy-group') {
      return 'policy-group';
    }
    if (validation.configType === 'outbound') {
      return 'outbound';
    }
    if (fallback === 'full' || fallback === 'proxy-chain' || fallback === 'policy-group') {
      return fallback;
    }
    return 'outbound';
  }

  private findNodeInList(nodes: Array<ProxyNode>, nodeId: string): ProxyNode | null {
    for (let index = 0; index < nodes.length; index++) {
      if (nodes[index].id === nodeId) {
        return nodes[index];
      }
    }
    return null;
  }

  // 跨所有订阅组查找节点：全局当前节点可能不在当前浏览的活动组中。
  findNodeInGroups(groups: Array<SubscriptionGroup>, nodeId: string): ProxyNode | null {
    if (nodeId.length === 0) {
      return null;
    }
    for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      const found = this.findNodeInList(groups[groupIndex].nodes, nodeId);
      if (found !== null) {
        return found;
      }
    }
    return null;
  }
}

export const NODES_CONTROLLER: NodesController = new NodesController();
