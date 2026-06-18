# Hey 未来开发计划（对标 v2rayNG · 稳步推进版）

> 制定日期：2026-06-05
> 基线：基于真实代码核对，而非声称状态。
> 关联文档：能力对照见 [`v2rayng-feature-map.md`](v2rayng-feature-map.md)，
> 早期评估见 [`roadmap.md`](roadmap.md)（本计划取代其中的阶段规划部分）。

本计划的原则是**稳步前进**：每个里程碑都是一个可独立验收、可单独发布的小闭环，
先打通"地基"（真机数据通路 + 内核能力），再逐层叠加体验与高级特性，避免在未验证的
通路上堆功能。

---

## 一、现状快照（2026-06-05 实测）

自 2026-06-03 路线图以来已落地：

- ✅ 相机扫码：`pages/Scanner.ets` 已接入 `@kit.ScanKit`（`scanBarcode.startScanForResult`）
- ✅ 分应用代理枚举：`pages/PerApp.ets` 已用 `bundleManager` 枚举已安装应用
- ✅ Assets 页模块化、NodeEdit 组件化、8 协议手动配置与解析

仍是关键缺口：

| 领域 | 现状 | 缺口 |
| --- | --- | --- |
| 真机 VPN 闭环 | ✅ **已真机验证通过（2026-06-15）**：`TUN fd → CGoSetTunFd → Xray native TUN → 出站` 端到端可上网 | 阻塞项解除，主线推进至 M1 |
| Native 桥接 | M1 已接通 7 个（含 `CGoQueryStats`/`CGoTestXray`/`CGoXrayVersion`），代码完成 | **待 `libxray.so` 重建（导出符号已加）+ 真机复测**；`CGoReadGeoFiles`/`CGoConvertShareLinks` 仍未接线 |
| 路由规则 | `buildRoutingRules` 仅 `geosite:cn` 旁路一条 | 广告拦截、自定义规则集、规则编辑器均未生效 |
| 订阅 | 多分组 + 手动更新 | **无自动更新、无去重、无正则过滤、无自定义 UA** |
| 分享导出 | 仅文本 | **无二维码生成** |
| 深链导入 | 无 | **URL Scheme / Want 导入未实现** |
| 高级路由 | 无 | 负载均衡 / 策略组 / 代理链均无 |
| 云备份 | 仅本地 ZIP | **无 WebDAV** |

---

## 二、里程碑总览

```text
M0 真机闭环验证 ──┬─→ M1 内核能力补全 ──→ M2 路由系统 ──→ M5 高级路由(可选)
（✅ 已完成）      └─→ M3 订阅与体验闭环  // 可与 M1/M2 并行
                                        └─→ M4 平台集成与分享  // 体验层，随时插入
```

每个里程碑控制在 1～2 周可验收的粒度。优先级：~~M0~~（已完成）> **M1 > M2 ≈ M3** > M4 > M5。

---

## 三、里程碑详情

### M0 · 真机数据通路闭环 ✅ 已完成（2026-06-15）

**目标**：在真机上跑通 `连接 → TUN → Xray → 出站 → 真实可上网`，得出"已验证"结论。

**结果**：真机闭环验证通过——`TUN fd → CGoSetTunFd → Xray native TUN inbound → 出站`
端到端可上网。后续功能不再建立在未验证通路上，主线推进至 M1。

**v2rayNG 对照**：`CoreVpnService` / `TProxyService` 的 TUN 建立与转发。
**验收标准**：真机浏览器可经代理访问；`docs/real-device-vpn-test.md` 清单跑通。

**后续点检（非阻塞，随手补）**：TUN 层 IPv6（当前 `isIPv6Accepted:false`）、
VPN 接口 `dnsAddresses` 改为读 `vpnDns` 设置（当前写死 `1.1.1.1/8.8.8.8`）、UDP 出站确认。

---

### M1 · Native 内核能力补全（🟡 代码完成，待重建 + 真机复测）

**目标**：把已编译进 `libxray.so` 但未接线的 CGo 函数接入 `napi_init.cpp`。

**进展（2026-06-15）**：`CGoQueryStats`/`CGoTestXray`/`CGoXrayVersion` 三项全链路接线完成：
- 构建：`scripts/build_libxray_ohos.sh` 的 version-script 增导出三个符号（原仅导出 4 个）
- Native：`napi_init.cpp` 新增 `queryStats`/`testXrayConfig`/`xrayVersion`，符号缺失时优雅降级
- 配置：`XrayConfig.ets` 增 `stats/metrics/policy` + `metrics_in` dokodemo inbound（127.0.0.1:10845）+ 路由规则
- 消费：VPN 扩展 `recordStats()` 查 metrics 端点写真实上下行；启动前 `CGoTestXray` 预检；About 页显示内核版本

**仍需**：用更新后的脚本重建 `libxray.so`（当前 `.so` 未导出这三个符号），真机复测流量/预检/版本，并确认新增 metrics inbound 不影响已验证的连接路径。

**任务**（按性价比排序）
1. `CGoQueryStats` → 真实上下行流量统计，替换当前 C++ 侧近似计数
2. `CGoTestXray` → 连接前配置预检，减少启动失败、提前报错
3. `CGoXrayVersion` → About 页显示真实内核版本
4. `CGoReadGeoFiles` → geo 文件校验与计数（Assets 页展示条目数）

**v2rayNG 对照**：`CoreServiceManager.queryAllOutboundTrafficStats()`、配置预检逻辑。
**验收标准**：运行态面板显示真实流量；非法配置在连接前被拦截并提示。
**依赖**：M0。

---

### M2 · 路由规则系统（核心能力差距）

**目标**：让 Route 页的开关真正影响生成的 Xray 配置，而非仅弹窗说明。

**进展（2026-06-18）**：自定义路由规则已贯通模型、持久化、Route 页管理与 Xray 配置生成：
- 模型：新增 `RoutingRule`，字段对齐 v2rayNG `RulesetItem` 的核心项（remarks/domain/ip/process/port/protocol/network/outboundTag/enabled/locked）
- UI：Route 页支持添加、编辑、删除、启停、上移/下移规则
- 配置：启用规则按列表顺序写入 `routing.rules`，位置在广告拦截之后、`routeOnly` 绕过规则之前；未知 outboundTag 回退 `proxy`
- 测试：新增单测覆盖启用/禁用规则、端口/协议/网络字段和规则顺序

**任务**
- ✅ 扩展 `core/XrayConfig.ets` 的 `buildRoutingRules`：支持多规则、广告拦截
  （`geosite:category-ads-all` → `block`）、用户自定义 域名/IP/端口/协议 规则
- ✅ 自定义规则集的持久化模型（参考 v2rayNG `RulesetItem`：
  `domain/ip/port/process/protocol/network/outboundTag/enabled`）
- ✅ 新建规则编辑器（增删改 + 上移/下移排序 + 启用开关）
- 预设规则集导入（白名单/黑名单/全局，对应 v2rayNG assets 内置规则）

**v2rayNG 对照**：`RoutingSettingActivity` / `RoutingEditActivity` / `RulesetItem`。
**验收标准**：开启广告拦截后广告域名走 block；自定义规则在连接后实际生效。
**依赖**：M0（需真机验证规则生效）。

---

### M3 · 订阅与节点体验闭环（可与 M1/M2 并行）

**目标**：补齐订阅自动化与节点批量管理，达到日常可用。

**任务**
- **订阅自动更新**：用鸿蒙后台任务/定时（`backgroundTaskManager` 或 `reminderAgent`）
  按 `updateInterval` 周期刷新；最小间隔保护（如 15 分钟）
- **正则过滤** `filter`：按节点名筛选导入
- **自定义 User-Agent** 与 `allowInsecureUrl`
- **代理经由更新**：运行中时通过本地 http 端口拉取订阅（GFW 内更新）
- **节点批量操作**：删除重复（去重键 = server+port+password）、批量测速后自动排序、
  测速后自动删除超时节点（`removeInvalidNodes` 已有，补"测速后自动"触发）

**v2rayNG 对照**：`SubscriptionUpdater`（WorkManager）、`AngConfigManager.updateConfigViaSub`、
`MainViewModel` 的批量操作。
**验收标准**：订阅到点自动刷新；去重/过滤/自动排序可用。
**依赖**：M0（测速依赖真机通路）。

---

### M4 · 平台集成与分享（体验层 · 可随时插入）

**目标**：补齐导入/分享/平台入口，对齐 v2rayNG 的便捷体验。

**任务**
- **URL Scheme / Want 深链导入**：对应 v2rayNG `v2rayng://install-config` 与
  `install-sub`，在 `EntryAbility.onCreate/onNewWant` 解析 Want 并导入
- **二维码生成**：节点分享生成 QR（鸿蒙 `@ohos.graphics` 或二维码库），
  补齐"显示二维码 / 单行链接 / 完整 JSON"三种分享形态
- **桌面服务卡片 / 快捷方式**：一键启停、扫码（对应 QSTile/Widget/Shortcuts）
- **常驻速度通知**：上下行实时显示（依赖 M1 的 `CGoQueryStats`）

**v2rayNG 对照**：`UrlSchemeActivity`、`share2QRCode`、`WidgetProvider`/`QSTileService`/`shortcuts.xml`。
**验收标准**：外部链接可一键导入；节点可生成二维码被另一台设备扫入。
**依赖**：M1（速度通知）；其余独立。

---

### M5 · 高级路由与云备份（进阶 · 可选）

**目标**：面向中高级用户的差异化能力。

**任务**
- **负载均衡（Balancer）**：`leastPing/leastLoad/random/roundRobin` +
  `observatory` 探测，生成 `routing.balancers`
- **策略组（PolicyGroup）**：从订阅按正则动态选成员
- **代理链（ProxyChain）**：多段代理串联
- **WebDAV 云备份/恢复**：BASIC 认证 + `MKCOL` 建目录 + 上传/下载 ZIP

**v2rayNG 对照**：`BalancerStrategyType`、`ServerGroupActivity`、`ServerProxyChainActivity`、
`WebDavManager`。
**验收标准**：策略组按延迟自动择优；WebDAV 备份可跨设备恢复。
**依赖**：M2（路由系统）、M3（订阅）。

---

## 四、协议与解析的并行点检（穿插各里程碑）

不单列里程碑，随手补齐：

- Reality 全参数（`spiderX`、`mldsa65`/`pqv`）解析与下发
- `flow`（`xtls-rprx-vision`）字段
- uTLS fingerprint（`fp`）
- Hysteria2 端口跳跃（`mport`）与 `obfs`
- WireGuard `.conf` 文件整段解析
- SOCKS 端口/动态端口/认证、VPN MTU、绕过局域网、代理共享等设置项

---

## 五、依赖关系与排期建议

| 周期 | 主线 | 并行 |
| --- | --- | --- |
| 第 1 段 | ~~M0 真机闭环~~ ✅ 完成 | 协议点检（解析层，纯逻辑可先做） |
| 第 2 段 | **M1 内核接线**（当前主线） | M3 订阅自动更新 |
| 第 3 段 | M2 路由系统 | M3 批量操作 + M4 深链导入 |
| 第 4 段 | M4 二维码/卡片/通知 | — |
| 第 5 段 | M5 高级路由 / WebDAV | — |

---

## 六、可立即编码 backlog（/loop 逐个完成）

> 本清单基于 **2026-06-15 实测代码**（非旧文档），仅收录「纯 ArkTS 逻辑、
> 无需重建 `.so`/真机、且 Xray-core 能实际运行」的项。每次循环触发取**第一条未完成项**，
> 端到端完成（逻辑+持久化+UI+校验）后在此打勾并补进度记录。

实测已完成（文档曾标为待办，实为已落地）：相机扫码、分应用枚举、**节点去重**
（`dedupeNodes` 全链路）、**订阅自定义 UA**（按分组持久化）。

- [x] 广告拦截路由生效（`adBlockEnabled` 开关 → `geosite:category-ads-all` → block，全模式生效，2026-06-15）
- [x] 订阅正则过滤 `filter`（`SubscriptionGroup.filter` 全链路：编辑页输入框 → 更新/更新全部时按节点名正则筛选，无效/空/零匹配回退全部，2026-06-15）
- [x] 测速后自动操作：`autoSortAfterTest` / `autoRemoveInvalidAfterTest` 设置项 + 设置页开关 + 批量测速后触发（按延迟排序 / 删除超时节点，2026-06-15）
- [x] 二维码生成：节点详情页用 `@kit.ScanKit` `generateBarcode.createBarcode` 渲染分享链接 QR + 复制链接（2026-06-15）
- [x] URL Scheme / Want 深链导入：`hey://install-sub` / `hey://install-config?url=` 注册 scheme + `EntryAbility.onCreate/onNewWant` 暂存 + Index `onPageShow` 解析导入（2026-06-15）

> ✅ 2026-06-15 批 backlog 全部完成。后续可补充项：负载均衡/策略组/代理链（M5）、
> WebDAV 云备份、路由预设规则集导入/导出、VPN MTU/接口地址可配、常驻速度通知（依赖 M1 重建后的真实流量）。

### 本会话代码自查清单（/loop 继续后续修复）

> 本会话所有改动均未编译/真机验证。此清单逐项静态审查，发现真实隐患即修，
> 纯「需真机验证」项不在此（标注即可）。每次循环取第一条未完成项。

- [x] 预检非阻断化：`CGoTestXray` 在设置 TUN fd 前对含 `tun` inbound 的整份配置 `core.New`，
      若构造期校验 fd 会误报 → 已改为**记警告不阻断**，`startNativeXray` 仍为失败判定源（2026-06-15）
- [x] ScanKit 二维码 API 字段核对：`CreateOptions.scanType/width/height` 与官方一致（2026-06-15）
- [x] i18n 总扫：脚本核对 `TRANSLATION_KEYS`≡`ZH`≡`EN`（各 327 键，完全一致）；246 个代码引用键全部有定义，动态键（`status.*`/`routing.mode.*`）均覆盖；无需修改（2026-06-15）
- [x] ArkTS 严格性扫描：本会话文件无 `any`；新增导入全部被引用；Record 索引/可选链/`as` 转型均沿用既有惯例。顺手清理 SubscriptionEdit 一处**既有**未用导入 `translate`（2026-06-15）
- [x] 字段一致性总扫：脚本核对 5 个构造点（DEFAULT_APP_SETTINGS/normalize/buildSettings/toDraft/buildDraft）字段完整无缺无多；`SubscriptionGroup.filter` 已贯通；Routing/Settings 两页回环保留全字段；无需修改（2026-06-15）
- [x] 深链/metrics 配置形状再核：metrics 配置与 Xray 官方一致（dokodemo 仅需 listen/port/protocol/tag/settings.address，无 network；stats{}+policy 4 flag；metrics_in→metrics_out；/debug/vars）；深链 manifest scheme/host≡解析器前缀、url 参数解码+回退、QR 来源回退均正确；无需修改（2026-06-15）

> ✅ 「继续后续修复」自查清单全部完成（2026-06-15）。净修复：① 预检非阻断化（真实潜在 bug）
> ② 清理 1 处既有未用导入。其余 4 项为静态核对，均通过。**仍待真机：M1 重建 + metrics/深链/QR 真机回归。**

> 不在本清单（Xray-core 不支持，避免做无用功）：TUIC、Hysteria2/Hysteria 运行态
> ——这些是 sing-box 协议，当前内核 `libXray`（Xray-core）无法运行，仅能解析不能连。

## 七、进度记录

| 日期 | 里程碑 | 变更 |
| --- | --- | --- |
| 2026-06-05 | — | 基于实测建立"稳步推进版"开发计划；确认扫码/分应用已落地，标注内核接线、路由、订阅自动更新、深链、二维码为后续重点 |
| 2026-06-15 | M0 | ✅ 真机数据通路闭环验证通过（TUN→Xray→出站→可上网），阻塞项解除；主线切至 M1 内核接线 |
| 2026-06-15 | M1 | 🟡 `CGoQueryStats`/`CGoTestXray`/`CGoXrayVersion` 全链路接线（构建脚本+native+XrayConfig metrics+扩展/About 消费）；待重建 `.so` + 真机复测 |
| 2026-06-15 | M2 | ✅ 广告拦截路由真正生效（`adBlockEnabled` 开关 → `geosite:category-ads-all` → block）；纠正实测：去重/自定义 UA 早已落地 |
| 2026-06-15 | M3 | ✅ 订阅正则过滤 `filter` 全链路（分组字段 + 编辑页 + 更新/更新全部按节点名筛选，零匹配/无效回退全部） |
| 2026-06-15 | M3 | ✅ 测速后自动操作（`autoSortAfterTest`/`autoRemoveInvalidAfterTest` 设置项 + 设置页「节点测速」开关 + 批量测速后排序/删超时） |
| 2026-06-15 | M4 | ✅ 二维码生成（节点详情页 `generateBarcode.createBarcode` 渲染分享链接 QR + 复制链接） |
| 2026-06-15 | M4 | ✅ URL Scheme / Want 深链导入（`hey://install-sub`/`install-config` scheme + EntryAbility 暂存 + Index 解析导入订阅/节点） |
| 2026-06-15 | 修复 | ✅ 预检改为非阻断（避免重建后 `CGoTestXray` 对 tun inbound 误报阻断已验证连接）；核对 ScanKit QR API 字段无误 |
| 2026-06-15 | 自查 | ✅ i18n 总扫通过：registry≡zh≡en（327 键），246 处代码引用全部有定义，无需修改 |
| 2026-06-15 | 自查 | ✅ ArkTS 严格性扫描：无 `any`、新增导入全部被用；清理 SubscriptionEdit 既有未用导入 `translate` |
| 2026-06-18 | M2 | ✅ 自定义路由规则编辑/生效（规则模型 + Route 页增删改/启停/排序 + `routing.rules` 生成 + 单测）；仍待预设规则集导入/导出 |
| 2026-06-15 | 自查 | ✅ 字段一致性总扫：AppSettings/SettingsDraft 5 个构造点字段完整一致，SubscriptionGroup.filter 贯通，无需修改 |
| 2026-06-15 | 自查 | ✅ 深链/metrics 配置形状核对 Xray 官方一致；自查清单收尾（净修复：预检非阻断 + 清理未用导入） |
