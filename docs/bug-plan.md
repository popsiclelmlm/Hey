# 待修复 Bug / 优化计划

记录已知但尚未修复的问题。VPN 核心（cgo TLS 墙）修复见 `docs/harmonyos-go-tls-wall.md`。

状态图例：🔴 待修 ｜ 🟡 待核实 ｜ 🟢 已修

---

## BUG-001 🟢 真实延迟"测全部"很慢（已修复，真机验证）

**现象**：节点列表"测试全部真实延迟"，71 个节点耗时约 4 分钟（真机日志 00:46→00:50+）。

**根因**：`DelayTester.measureNodeOutbound` 对每个节点都在 TaskPool worker 上：
1. 冷加载 31MB 的 `libxray.so`（每个 worker 各自一份 Go 运行时）；
2. `CGoPing` 现建一个临时 Xray 实例、连代理、ping、再拆掉。

71 个节点 = 71 次"冷起核 + 建 Xray + ping"，即使有并发也很慢。
（注：worker 化本身是对的——之前 cgo 在 UI 线程会崩，根本跑不完；现在能跑了，慢的代价才暴露出来。见 `harmonyos-go-tls-wall.md` §9 与 DelayTester 改动。）

**根因更正**：`dlopen` 是**进程级**，libxray 只加载一次、所有 taskpool worker 共享同一个 Go
运行时——所以并非"每 worker 冷加载 31MB"。真正瓶颈是 napi `PingOutbound` 把配置写**同一个文件**
`hey-ping-config.json` + 所有 ping 用**同一个 socks 端口** `DELAY_TEST_SOCKS_PORT(10825)`
（`CGoGetFreePorts` 未导出，`getNativeFreePorts` 失败回退到固定端口）。共享端口/共享文件迫使并发
ping 实际串行 → 71 节点 × ~3s ≈ 4 分钟。

**已修复（纯 ArkTS + 小改 napi，不动 .so 导出）**：
- ArkTS 用**流式并发池**（`Index.runRealDelayBatch`）：开 N 个"槽"（N=并发数，封顶 32），槽 w 固定用
  端口 `DELAY_TEST_BATCH_PORT_BASE(11200)+w`，槽内顺序领取节点测速 → 并发的 ping 各占独立端口、
  互不撞；
- napi `PingOutbound` 按端口分配置文件名 `hey-ping-<port>.json` → 并发写不再互相覆盖；
- **逐个完成逐个刷新**：每个节点一测完立即 `markNodeDelay` 刷新该行（内存态，含"全部"视图），
  持久化按阈值（每 24 个）后台 `saveNodeDelays` 批量落库；
- `libxray.so` **保持原版不变**（VPN 零回归风险）；`measureNodeOutbound` 增加显式 `socksPort` 入参。

> 走过弯路：先尝试给 libXray 加 `CGoPingBatch` 原生批量导出（已成功复现 OHOS fork 构建并编出带该导出
> 的 .so，见 §9.4 配方验证），但批量是"一次返回一整批"、无法边测边回（用户要"测一个更新一个"），
> 故弃用、还原原版 .so，改走上面的流式逐节点方案。

**真机验证（ALN-AL80，2026-06-22）**：66 节点"测试配置真连接"——结果**逐个出现**（先 348/317ms，其余仍
"测速中"），几十秒内全部完成（原 ~4 分钟），无崩溃；VPN 连接/断开正常、状态栏 VPN 图标正常、日志无
SIGSEGV（确认换文件名的 napi 改动不影响 VPN 数据面）。

**严重度**：中（功能可用，但大列表体验差）→ **已解决**。

---

## BUG-002 🟢 延迟测试进行中，点其它延迟测试"完全没反应"

**现象**：上面的"测全部真实延迟"还在跑（~4 分钟）时，去点单个节点的"TCP 延迟"，UI 毫无反应、数值不更新。

**根因**：`Index.ets` 的 `testVisibleNodeDelay` 开头有全局锁守卫：
```ts
if (this.delayTesting) { return; }   // 静默早退，无任何提示
```
批量测试期间 `delayTesting = true`，后续任何延迟测试点击都被静默拦截 → 看起来"没反应"。

**已修复**：守卫命中时弹 toast `home.delayTesting`（"正在测速，请稍候…"），不再静默早退。
见 `Index.ets:testVisibleNodeDelay` 与 I18n 新增 key `home.delayTesting`（三处）。

**已真机验证（行为）**：真测试运行中再点"测试 TCP 延迟"，被守卫分支拦下、原测试继续、无崩溃。
（toast 是 HarmonyOS 系统级瞬时窗口，`snapshot_display`/`uitest dumpLayout` 均抓不到其文本，故只能行为验证 + 编译验证。）

**严重度**：中（易误判为功能坏掉）。

---

## BUG-003 🟢 节点列表延迟值测完不回显

**现象**：用户反馈延迟测完"数值没有更新"。真机日志证明真实延迟**已算出并返回**（71/71 全部 ok），但列表里的延迟数值不刷新。

**根因（已定位）**：`Index.ets` 节点列表 `ForEach` 的 key 是 `${index}-${node.id}`，**不含延迟值**。
延迟测完 `applySubscriptionsState` 换了 `nodes`（新对象），但 key 不变 → ForEach 按 key 复用旧子组件、
不重跑 item builder（`delayText`/`delayColor` 是在 builder 里现算的）→ 行不刷新。这与 BUG-005 是**同一根因**
（ArkUI ForEach key 稳定即跳过重渲染，见全局 memory `arkui-foreach-key-stale`）。

**已修复**：ForEach key 改为 `${index}-${node.id}-${选中态}-${node.delayStatus}-${node.delayMs}`，
任何选中态/延迟值变化都强制对应行重渲染。见 `Index.ets:NodeList()`。

**已真机验证（ALN-AL80）**：TCP 测试后所有节点延迟值实时刷新（899→106、766→100…），颜色随值变绿/红；
随后真连接测试又把值更新为真延迟（90/92ms…），两轮均正常回显。

**严重度**：中（看起来像测速坏掉）。

---

## BUG-004 🟢 延迟测试缺 loading 指示（首次冷调用像卡死）

**现象**：单点一个节点测延迟，首次约 1-2 秒无任何反馈（worker 冷加载核），看起来像"没反应"。

**根因**：`markNodeDelay(node.id, -1, 'testing', ...)` 本已设"测速中"态（`node.delay.testing` 文案），
但两个原因让它不显示：① 同 BUG-003 的 ForEach key 冻结，testing 态写进了 @State 却不重渲染；
② `markNodeDelay` 只更新 `this.nodes`，而"全部"视图列表来自 `subscriptionGroups`，testing 态进不去那个视图。

**已修复**：
- ForEach key 现含 `node.delayStatus` → testing→结果 的切换强制重渲染（随 BUG-003 一并解决）；
- `markNodeDelay` 同步把 testing 态写进 `subscriptionGroups` 里对应节点，"全部"视图也能显示"测速中"。
见 `Index.ets:markNodeDelay` / `patchNodeDelay`。

**已真机验证（ALN-AL80）**：发起测试瞬间，全部节点行立即显示"测速中"（含选中行同时保留对勾），结果回来再替换为数值。

**严重度**：低（体验）。

---

## BUG-005 🟢 跨订阅切换节点后，原订阅的节点仍显示选中

**现象**：添加两个订阅（group）。连接订阅 1 的节点 A；切到订阅 2 选节点 B；订阅 1 的节点 A **仍是选中状态**（B 未变选中）。在"全部"视图（所有订阅节点拼在一个列表）下最易复现。

**根因更正**：原先怀疑是 `SubscriptionStore.selectNode` 没更新 `profile.selectedNodeId`，
**经复查是误诊**——`selectNode` 命中 group 时已设 `group.selectedNodeId` + `profile.selectedGroupId`，
而 `normalize`（`SubscriptionStore.ets:465-475`）会从 active group 反推 `profile.selectedNodeId`，
所以 `state.selectedNodeId` / `this.selectedNodeId` 实际是对的（=B）。

真凶与 BUG-003 相同：节点列表 `ForEach` 的 key `${index}-${node.id}` **不含选中态**。
选中从 A 换到 B 时列表内容（数组元素 id）没变 → ForEach 按 key 复用旧行、不重跑 item builder，
`isSelected: node.id === this.selectedNodeId`（@Prop，本身响应式）压根没被重新求值 → A 行的选中态冻结、B 行不亮。

**已修复**：ForEach key 编码选中态（`${node.id === this.selectedNodeId ? 'S' : 'U'}`），
切换选中时新旧两行 key 均变化、强制重渲染。`SubscriptionStore.selectNode` 无需改动。见 `Index.ets:NodeList()`。

**已真机验证（ALN-AL80）**：同列表内点香港01，高亮从香港02 正确移过去；切到"手动导入"组显示其自身选中（proxy）；切回 sub 组香港01 仍选中、不串选。

**严重度**：中（功能性，易让用户以为切换没生效）。

---

## 关联：VPN 修复收尾项（详见 harmonyos-go-tls-wall.md §9.5）

- 回退构建脚本里尚未补的 openharmony 分支（让 .so 可复现）。
- About 页 `BUNDLED_XRAY_VERSION` 与实际 v1.250803.0 对不上，需随脚本重新 stamp。
- ~~当前真机版含临时诊断埋点（DelayTester 的 `[M]`/`[W]` hilog），收尾时清掉。~~ ✅ 已清理。
- sing-box 核仍走旧 GOOS=android 路（未修），后续迁移到 OHOS fork + SOCKS 入站。
