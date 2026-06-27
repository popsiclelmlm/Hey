/**
 * 运行中改变「当前选中节点 / 当前配置」后，对实时隧道应采取的动作决策（纯函数）。
 *
 * 实时隧道在启动时拿到的是 outbound 配置快照，运行中改 ProfileStore/SubscriptionStore
 * 对它零影响。若界面已把「当前节点」切到新值却不动隧道，就会出现「界面显示已切换、流量仍
 * 走旧节点」的不一致。这里把各页面「该不该热切换 / 该不该断开」的判断集中成可单测的纯决策，
 * 与 SettingsChange.ets 的重启决策同构。
 */
export type RuntimeReconnectAction = 'none' | 'reconnect' | 'stop';

export const RUNTIME_RECONNECT_NONE: RuntimeReconnectAction = 'none';
export const RUNTIME_RECONNECT_RECONNECT: RuntimeReconnectAction = 'reconnect';
export const RUNTIME_RECONNECT_STOP: RuntimeReconnectAction = 'stop';

// 选中 / 切换某节点：运行中且目标节点有效且与当前不同 → 热切换重连。
export function decideNodeSwitchAction(running: boolean, currentNodeId: string, nextNodeId: string): RuntimeReconnectAction {
  if (!running) {
    return RUNTIME_RECONNECT_NONE;
  }
  if (nextNodeId.length === 0 || nextNodeId === currentNodeId) {
    return RUNTIME_RECONNECT_NONE;
  }
  return RUNTIME_RECONNECT_RECONNECT;
}

// 更新订阅等会改写「当前节点」outbound 的操作：运行中且新配置有效且与旧配置不同 → 热切换重连。
export function decideConfigChangeAction(running: boolean, valid: boolean, previousOutbound: string, nextOutbound: string): RuntimeReconnectAction {
  if (!running || !valid) {
    return RUNTIME_RECONNECT_NONE;
  }
  return previousOutbound === nextOutbound ? RUNTIME_RECONNECT_NONE : RUNTIME_RECONNECT_RECONNECT;
}

// 删除节点：运行中且删除的是当前连接节点 → 断开。不静默改连到其它服务器（用户没有选它）。
export function decideActiveNodeRemovalAction(running: boolean, removingActiveNode: boolean): RuntimeReconnectAction {
  return running && removingActiveNode ? RUNTIME_RECONNECT_STOP : RUNTIME_RECONNECT_NONE;
}
