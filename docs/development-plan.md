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
| 路由规则 | ✅ 广告拦截、自定义规则、预设规则集导入/导出均已写入 `routing.rules` | 仍待真机验证规则实效；高级出站目标（策略组/负载均衡）归入 M5 |
| 订阅 | 多分组 + 手动/批量更新 + 前台到期刷新 + 本地 HTTP 代理经由更新 | 后台定时调度仍待补齐 |
| 分享导出 | 文本/文件导出 + 节点二维码 + 系统分享面板 | 仍待真机回归不同分享目标兼容性 |
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

**后续点检（非阻塞，随手补）**：UDP 出站确认。VPN 接口 `dnsAddresses`
已于 2026-06-18 改为读取 `vpnDns` 设置；TUN 层 IPv6 已完成设置接线、
`VpnConfig` 地址/路由生成与 Xray outbound Happy Eyeballs，仍待真机回归。

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

**进展（2026-06-18 续）**：预设规则集导入/导出已落地：
- 预设：内置大陆白名单/大陆黑名单/全局/伊朗白名单/俄罗斯白名单
- 导入：导入预设或剪贴板规则数组 JSON 时保留 `locked` 规则并替换未锁定规则
- 导出：当前规则可导出为 v2rayNG 风格规则数组 JSON 到剪贴板
- UI：规则编辑器补 `locked` 开关，规则列表显示锁定标记

**任务**
- ✅ 扩展 `core/XrayConfig.ets` 的 `buildRoutingRules`：支持多规则、广告拦截
  （`geosite:category-ads-all` → `block`）、用户自定义 域名/IP/端口/协议 规则
- ✅ 自定义规则集的持久化模型（参考 v2rayNG `RulesetItem`：
  `domain/ip/port/process/protocol/network/outboundTag/enabled`）
- ✅ 新建规则编辑器（增删改 + 上移/下移排序 + 启用开关）
- ✅ 预设规则集导入/导出（白名单/黑名单/全局等；剪贴板 JSON 导入/导出；保留 locked 规则）

**v2rayNG 对照**：`RoutingSettingActivity` / `RoutingEditActivity` / `RulesetItem`。
**验收标准**：开启广告拦截后广告域名走 block；自定义规则在连接后实际生效。
**依赖**：M0（需真机验证规则生效）。

---

### M3 · 订阅与节点体验闭环（可与 M1/M2 并行）

**目标**：补齐订阅自动化与节点批量管理，达到日常可用。

**进展（2026-06-18 续）**：订阅分组重排已落地：
- 数据：新增纯函数 `moveSubscriptionGroup`，store 持久化分组顺序且保留当前选中分组 ID
- UI：订阅分组列表滑动操作补「上移/下移」，首尾项禁用越界动作
- 测试：新增单测覆盖上移、下移、越界不变和源列表不被原地修改

**进展（2026-06-18 续）**：订阅级不安全 URL 开关已落地：
- 模型：`SubscriptionGroup.allowInsecureUrl` 持久化并兼容旧存储默认 `false`
- UI：订阅编辑页新增「允许不安全订阅链接」开关
- 更新：保存/更新订阅时默认拒绝 `http://`，开启后允许；`https://` 保持默认可用，重定向同样遵循该开关
- 测试：新增单测覆盖 `https://`、HTTP 默认拒绝、HTTP 开启允许、非 HTTP(S) 拒绝

**进展（2026-06-18 续）**：节点批量删除全部已落地：
- Store/Controller：新增清空当前订阅分组节点能力，分组本身保留，选中节点清空
- UI：Nodes 菜单补「删除配置」，执行前二次确认
- 日志：删除后记录删除数量，并同步空状态

**进展（2026-06-18 续）**：订阅自动更新设置与前台到期刷新已落地：
- 模型：`SubscriptionGroup.autoUpdate` / `updateIntervalMinutes` 持久化，默认 1440 分钟、最小 15 分钟，兼容旧存储
- UI：订阅编辑页新增「启用自动更新」和「更新间隔（分钟）」设置
- 更新：首页启动/返回时节流检查到期订阅，复用订阅拉取、过滤和保存逻辑；批量/自动刷新不再切换当前分组
- 测试：新增纯函数单测覆盖间隔归一化、到期窗口、禁用/无 URL/未开启自动更新不触发

**进展（2026-06-18 续）**：运行中经由本地 HTTP 代理更新订阅已落地：
- Xray：设置开启时生成 `http-in` 本地 HTTP inbound（`127.0.0.1:10808`），并将该 inbound 显式路由到 `proxy`
- 共享：开启「允许来自局域网的连接」时，`http-in.listen` 改为 `0.0.0.0:10808`，对齐 v2rayNG 本地代理共享语义；内部订阅更新仍走 loopback
- 设置：Settings 页新增「追加本地 HTTP 代理」开关，保存后参与运行配置生成
- 更新：手动更新、订阅详情更新、扫码订阅导入、批量更新全部和前台到期刷新均可优先使用本地 HTTP 代理；代理不可用时回退直连
- 测试：新增配置生成单测覆盖开关关闭/开启时 HTTP inbound 与代理路由输出

**任务**
- **订阅自动更新**：前台到期刷新已完成；下一步用鸿蒙后台任务/定时（`backgroundTaskManager` 或 `reminderAgent`）
  在应用不打开时也按 `updateInterval` 周期刷新
- **正则过滤** `filter`：按节点名筛选导入（2026-06-15 已完成）
- **自定义 User-Agent** 与订阅级 `allowInsecureUrl` 已完成
- **订阅分组重排**：上移/下移并持久化顺序（2026-06-18 已完成）
- **批量更新全部**：订阅页顶部刷新按钮更新全部启用订阅分组（已完成）
- **代理经由更新**：运行中时通过本地 HTTP 端口拉取订阅（2026-06-18 已完成）
- **节点批量操作**：删除全部、删除重复、批量测速后自动排序、测速后自动删除超时节点已完成；
  其他批处理能力继续对照 v2rayNG 点检

**v2rayNG 对照**：`SubscriptionUpdater`（WorkManager）、`AngConfigManager.updateConfigViaSub`、
`MainViewModel` 的批量操作。
**验收标准**：订阅到点自动刷新；去重/过滤/自动排序可用。
**依赖**：M0（测速依赖真机通路）。

---

### M4 · 平台集成与分享（体验层 · 可随时插入）

**目标**：补齐导入/分享/平台入口，对齐 v2rayNG 的便捷体验。

**进展（2026-06-18 续）**：完整自定义 Xray 配置导入已落地：
- 校验：JSON 导入入口自动区分单个 outbound 与完整 Xray config（`inbounds` + `outbounds`）
- 文件：JSON 导入页可通过系统文件选择器读取 `.json`/`.txt`/`.conf` 配置文件，读取后沿用同一套校验与导入流程
- 存储：手动节点和当前 profile 记录 `configType`，旧 outbound 节点保持兼容
- 运行：完整 config 启动时直接传给 VPN 扩展，不再套用 Hey 生成的 TUN/routing/DNS/HTTP 代理配置
- 导出/清理：完整 config 节点可作为 JSON 文本导出，删除无效节点和去重不会误判为无效 outbound

**进展（2026-06-18 续）**：节点配置文件导出已落地：
- Export 页可将当前分组导出内容复制到剪贴板或通过系统文件选择器保存为 `.txt`
- 导出内容复用节点导出模型，分享链接节点输出 share link，完整自定义配置输出 JSON 文本
- ✅ 系统分享面板：Export 页批量文本、节点详情单节点链接均可拉起 Harmony `sendData` 分享；无可用目标时回退复制剪贴板（2026-06-18）

**任务**
- ✅ **完整自定义配置导入**：对应 v2rayNG `ServerCustomConfigActivity` 的粘贴导入与运行路径
  （2026-06-18 已完成；文件选择导入已补齐，高级编辑待补）
- ✅ **文件导出**：Export 页保存当前分组节点到 `.txt` 文件（2026-06-18 已完成；系统分享面板已补齐）
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
- ✅ WireGuard `.conf` 文件整段解析（2026-06-18 已完成：`[Interface]`/`[Peer]` 文本或文件导入转为 Xray wireguard outbound）
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
> WebDAV 云备份、VPN MTU/接口地址可配、常驻速度通知（依赖 M1 重建后的真实流量）。

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
| 2026-06-18 | M2 | ✅ 自定义路由规则编辑/生效（规则模型 + Route 页增删改/启停/排序 + `routing.rules` 生成 + 单测） |
| 2026-06-18 | M2 | ✅ 预设规则集导入/导出（5 组内置预设 + 剪贴板 JSON 导入/导出 + locked 规则保留 + 单测）；M2 路由规则主功能闭环，仍待真机验证规则实效 |
| 2026-06-18 | M3 | ✅ 订阅分组重排（纯排序函数 + Store 持久化 + Subs 页滑动上移/下移 + 单测）；批量更新全部确认已落地 |
| 2026-06-18 | 协议点检 | ✅ WireGuard `.conf` 整段解析完成，支持粘贴/扫码/文件导入 `[Interface]` + `[Peer]` 配置并归一化为 Xray outbound |
| 2026-06-18 | M3 | ✅ 订阅级不安全 URL 开关（编辑页 `allowInsecureUrl` + 保存/更新 HTTP 校验 + 重定向校验 + 单测）；默认拒绝 `http://` 订阅，开启后允许 |
| 2026-06-18 | M3 | ✅ 当前分组删除全部配置（Nodes 菜单确认弹窗 + Store/Controller 清空 active group nodes + 删除数量日志）；补齐 v2rayNG `removeAllServer` 的日常批处理路径 |
| 2026-06-18 | M3 | ✅ 订阅自动更新设置与前台到期刷新（`autoUpdate`/`updateIntervalMinutes` + 1440/15 分钟规则 + 首页节流到期刷新 + 单测）；后台任务调度仍待补 |
| 2026-06-18 | M3 | ✅ 运行中经由本地 HTTP 代理更新订阅（`appendHttpProxy` 设置 + `http-in` inbound 10808 + 订阅拉取 `usingProxy` 优先/直连回退 + 单测） |
| 2026-06-18 | M3 | ✅ 本地 HTTP 代理共享开关生效（`proxySharingEnabled` 开启时 `http-in.listen=0.0.0.0`，默认仍为 `127.0.0.1`，补配置生成单测） |
| 2026-06-18 | M0 补点 | ✅ VPN 接口 DNS 不再写死，`settings.vpnDns` 会规范化后写入 Harmony `VpnConfig.dnsAddresses`，空值回退 `1.1.1.1/8.8.8.8` |
| 2026-06-18 | M4 | ✅ 系统分享面板接入（批量导出文本 + 单节点分享链接走 `ohos.want.action.sendData`，失败回退剪贴板，并补分享 Want 单测） |
| 2026-06-18 | M0 补点 | ✅ TUN IPv6 设置接线完成（Settings `preferIpv6` 开关持久化 + VPN `fd00:172:19::2/126` 地址 + `::/0` 默认路由 + `isIPv6Accepted`） |
| 2026-06-18 | M0 补点 | ✅ `preferIpv6` 继续贯通到生成的 Xray outbound：开启时写入 `sockopt.domainStrategy=UseIP` 与 `happyEyeballs.prioritizeIPv6/interleave`，并覆盖 fragment 共存单测 |
| 2026-06-15 | 自查 | ✅ 字段一致性总扫：AppSettings/SettingsDraft 5 个构造点字段完整一致，SubscriptionGroup.filter 贯通，无需修改 |
| 2026-06-15 | 自查 | ✅ 深链/metrics 配置形状核对 Xray 官方一致；自查清单收尾（净修复：预检非阻断 + 清理未用导入） |
