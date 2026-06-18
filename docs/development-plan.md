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
- ✅ 分应用代理：`pages/PerApp.ets` 已用 `bundleManager` 枚举已安装应用，并补齐全选/清除/反选、自动选择代理应用、剪贴板导入/导出包名列表
- ✅ Assets 页模块化、NodeEdit 组件化、8 协议手动配置与解析

仍是关键缺口：

| 领域 | 现状 | 缺口 |
| --- | --- | --- |
| 真机 VPN 闭环 | ✅ **已真机验证通过（2026-06-15）**：`TUN fd → CGoSetTunFd → Xray native TUN → 出站` 端到端可上网 | 阻塞项解除，主线推进至 M1 |
| Native 桥接 | M1 已接通 12 个（含 `CGoQueryStats`/`CGoTestXray`/`CGoXrayVersion`/`CGoReadGeoFiles`/`CGoCountGeoData`/`CGoGetFreePorts`/`CGoConvertShareLinksToXrayJson`/`CGOConvertXrayJsonToShareLinks`），代码完成 | **待 `libxray.so` 重建（导出符号已加）+ 真机复测**；仅 `CGoRunXray` 仍闲置 |
| 路由规则 | ✅ 广告拦截、自定义规则、预设规则集导入/导出均已写入 `routing.rules`，`routeOnly` 会控制 process 规则输出和 sniffing routeOnly | 仍待真机验证规则实效；高级出站目标（策略组/负载均衡）归入 M5 |
| 订阅 | 多分组 + 手动/批量更新 + 前台到期刷新 + 本地 HTTP 代理经由更新 + WorkScheduler 后台调度接线；本地 SOCKS 入口按 v2rayNG 默认开启，可供代理经由能力使用 | 待真机触发回归后台唤醒路径 |
| 分享导出 | 文本/文件导出 + 节点二维码 + 订阅链接二维码 + 系统分享面板 | 仍待真机回归不同分享目标兼容性 |
| 速度通知 | 🟡 常驻通知代码完成；连接运行且速度显示开启时每 3 秒刷新上传/下载速率与累计流量，停止或关闭设置时取消 | 待真机通知权限弹窗、通知中心展示与后台留存回归 |
| 深链导入 | ✅ Harmony Want / `hey://install-sub` / `hey://install-config` 已接入 EntryAbility 与首页解析 | 仍待真机回归外部应用触发路径 |
| 桌面入口 | 🟡 Harmony 服务卡片基础入口完成；2×2 卡片提供 toggle/start/stop/scan 四个控制深链入口，并通过保存 formId + updateForm 同步运行态 | 待真机添加卡片、点击调起和系统刷新回归 |
| 高级路由 | 代理链、策略组/负载均衡运行核心已可通过 JSON 导入生成；添加节点页已可从已有普通节点创建代理链/策略组并保存为手动节点；策略组可按订阅分组与节点名正则动态展开成员；路由规则可选择当前高级出站目标 | 真机组合场景回归待补 |
| 云备份 | 剪贴板 JSON 备份 + WebDAV ZIP 云备份/还原已落地，默认 `backups/backup_ng.zip`，恢复兼容旧 JSON 包 | 真 WebDAV 服务兼容回归待补 |

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
`ipv6Enabled` 负责 `VpnConfig` 地址/路由，`preferIpv6` 负责 Xray outbound Happy Eyeballs；VPN MTU 与接口地址方案也已改为
Settings 可配置，MTU 默认值已对齐 v2rayNG 为 1500 并写入 Harmony `VpnConfig` 与 Xray TUN inbound，接口地址方案写入
Harmony `VpnConfig.addresses`；VPN 绕过 LAN 也已按 v2rayNG 三态写入 Harmony
`VpnConfig.routes`，仍待真机回归。

---

### M1 · Native 内核能力补全（🟡 代码完成，待重建 + 真机复测）

**目标**：把已编译进 `libxray.so` 但未接线的 CGo 函数接入 `napi_init.cpp`。

**进展（2026-06-15）**：`CGoQueryStats`/`CGoTestXray`/`CGoXrayVersion` 三项全链路接线完成：
- 构建：`scripts/build_libxray_ohos.sh` 的 version-script 增导出三个符号（原仅导出 4 个）
- Native：`napi_init.cpp` 新增 `queryStats`/`testXrayConfig`/`xrayVersion`，符号缺失时优雅降级
- 配置：`XrayConfig.ets` 按 `speedEnabled` 增 `stats/metrics/policy` + `metrics_in` dokodemo inbound（127.0.0.1:10845）+ 路由规则
- 消费：VPN 扩展 `recordStats()` 查 metrics 端点写真实上下行；启动前 `CGoTestXray` 预检；About 页显示内核版本

**进展（2026-06-18 续）**：`CGoReadGeoFiles`/`CGoCountGeoData` 接线完成：
- 构建：version-script 继续导出 `CGoReadGeoFiles`/`CGoCountGeoData`
- Native：`napi_init.cpp` 新增 `readGeoFiles`/`countGeoData`，符号缺失时优雅降级
- 消费：Assets 页对 `geosite.dat`/`geoip.dat` 生成 sidecar 计数 JSON，并在文件状态展示分类数/规则数

**进展（2026-06-18 续）**：`CGoGetFreePorts` 接线完成：
- 构建：version-script 继续导出 `CGoGetFreePorts`
- Native：`napi_init.cpp` 新增 `getFreePorts`，符号缺失时优雅降级
- 消费：真实延迟测速优先使用 native 空闲端口生成临时 SOCKS inbound；本地 SOCKS 动态端口在连接前读取空闲端口写入 `socks-in`，失败分别回退旧端口 `10825` / 用户设置端口

**进展（2026-06-18 续）**：`CGoConvertShareLinksToXrayJson`/`CGOConvertXrayJsonToShareLinks` 接线完成：
- 构建：version-script 继续导出两个分享转换符号
- Native：`napi_init.cpp` 新增 `convertShareLinksToXrayJson`/`convertXrayJsonToShareLinks`，符号缺失时优雅降级
- 消费：导入页在内置单节点解析失败后调用 native 转换，支持 v2rayN 多行/base64 与 Clash.Meta YAML，提取返回配置中的 outbounds 保存为手动节点

**仍需**：用更新后的脚本重建 `libxray.so`（当前 `.so` 未导出这些新增符号），真机复测流量/预检/版本/Geo 计数/动态测速端口/动态本地 SOCKS 端口/native 分享转换，并确认新增 metrics inbound 不影响已验证的连接路径。

**任务**（按性价比排序）
1. `CGoQueryStats` → 真实上下行流量统计，替换当前 C++ 侧近似计数
2. `CGoTestXray` → 连接前配置预检，减少启动失败、提前报错
3. `CGoXrayVersion` → About 页显示真实内核版本
4. ✅ `CGoReadGeoFiles` / `CGoCountGeoData` → geo 文件校验与计数（Assets 页展示条目数，2026-06-18）
5. ✅ `CGoConvertShareLinksToXrayJson` / `CGOConvertXrayJsonToShareLinks` → 分享文本与 Xray JSON 互转（导入兜底已用，2026-06-18）

**v2rayNG 对照**：`CoreServiceManager.queryAllOutboundTrafficStats()`、配置预检逻辑。
**验收标准**：运行态面板显示真实流量；非法配置在连接前被拦截并提示。
**依赖**：M0。

---

### M2 · 路由规则系统（核心能力差距）

**目标**：让 Route 页的开关真正影响生成的 Xray 配置，而非仅弹窗说明。

**进展（2026-06-18）**：自定义路由规则已贯通模型、持久化、Route 页管理与 Xray 配置生成：
- 模型：新增 `RoutingRule`，字段对齐 v2rayNG `RulesetItem` 的核心项（remarks/domain/ip/process/port/protocol/network/outboundTag/enabled/locked）
- UI：Route 页支持添加、编辑、删除、启停、上移/下移规则
- 配置：启用规则按列表顺序写入 `routing.rules`，位置在广告拦截之后、`routeOnly` 绕过规则之前；未知 outboundTag 回退 `proxy`；`routeOnly` 开关会按 v2rayNG 语义控制 process 规则输出并写入 TUN sniffing `routeOnly`
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

**进展（2026-06-18 续）**：订阅 WorkScheduler 后台调度已接入：
- 调度：按已开启自动更新且 URL 有效的订阅分组计算最短更新间隔，注册持久重复 `workScheduler` 任务
- 后台：新增 `SubscriptionUpdateWorkAbility`，系统唤醒时调用到期刷新逻辑，完成后重新同步调度状态并写入诊断日志
- 同步：订阅增删改、启停、批量/到期更新以及首页启动/回前台都会刷新 WorkScheduler 注册
- 测试：新增调度计划纯函数单测覆盖无任务、最短间隔和最小 15 分钟归一化

**进展（2026-06-18 续）**：运行中经由本地 HTTP 代理更新订阅已落地：
- Xray：设置开启时生成 `http-in` 本地 HTTP inbound（`127.0.0.1:10808`），并将该 inbound 显式路由到 `proxy`
- 共享：开启「允许来自局域网的连接」时，`http-in.listen` 改为 `0.0.0.0:10808`，对齐 v2rayNG 本地代理共享语义；内部订阅更新仍走 loopback
- 设置：Settings 页新增「追加本地 HTTP 代理」开关，保存后参与运行配置生成
- 更新：手动更新、订阅详情更新、扫码订阅导入、批量更新全部和前台到期刷新均可优先使用本地 HTTP 代理；代理不可用时回退直连
- 测试：新增配置生成单测覆盖开关关闭/开启时 HTTP inbound 与代理路由输出

**任务**
- **订阅自动更新**：WorkScheduler 后台任务代码已接入；下一步真机验证应用不打开时的周期唤醒与网络拉取
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
- 编辑：节点详情可打开手动 custom/full 节点，编辑配置名称与 JSON 内容；保存时重新校验并更新原节点，若该节点正被选中则同步当前 profile

**进展（2026-06-18 续）**：节点配置文件导出已落地：
- Export 页可将当前分组导出内容复制到剪贴板或通过系统文件选择器保存为 `.txt`
- 导出内容复用节点导出模型，分享链接节点输出 share link，完整自定义配置输出 JSON 文本
- ✅ 系统分享面板：Export 页批量文本、节点详情单节点链接均可拉起 Harmony `sendData` 分享；无可用目标时回退复制剪贴板（2026-06-18）

**任务**
- ✅ **完整自定义配置导入**：对应 v2rayNG `ServerCustomConfigActivity` 的粘贴导入与运行路径
  （2026-06-18 已完成；文件选择导入和高级编辑已补齐）
- ✅ **文件导出**：Export 页保存当前分组节点到 `.txt` 文件（2026-06-18 已完成；系统分享面板已补齐）
- ✅ **URL Scheme / Want 深链导入**：对应 v2rayNG `v2rayng://install-config` 与
  `install-sub`，在 `EntryAbility.onCreate/onNewWant` 解析 Want 并导入
- ✅ **控制深链入口**：对应 v2rayNG Tasker/shortcuts/QS tile 的基础控制动作，
  支持 `hey://control?action=start|stop|toggle|scan` 和短 URI
  `hey://start` / `hey://stop` / `hey://toggle` / `hey://scan`
- ✅ **开机自动连接设置**：对应 v2rayNG `pref_is_booted`/`BootReceiver`，
  设置页可持久化“开机自动连接”；Harmony `AUTO_STARTUP` 启动原因会在主页加载设置和当前节点后触发启动当前节点
  （受系统自启动开关/权限控制，仍需真机重启回归）
- ✅ **二维码生成**：节点分享与订阅链接分享生成 QR（ScanKit `generateBarcode.createBarcode`），
  节点补齐"显示二维码 / 单行链接 / 完整 JSON"三种分享形态；订阅详情页可显示订阅 URL 二维码并复制/系统分享
- 🟡 **桌面服务卡片 / 快捷方式**：一键启停、扫码（对应 QSTile/Widget/Shortcuts）；
  Harmony `ControlCardAbility` 已注册 2×2 ArkTS 服务卡片，卡片通过 `FormLink`
  跳转 `hey://toggle` / `hey://start` / `hey://stop` / `hey://scan`
  复用现有控制深链；卡片 formId 与最近运行态已持久化，首页运行态刷新会同步
  `statusLabel`/`statusDetail`/主按钮动作并按 3 秒节流调用 `updateForm` 更新桌面卡片；待真机添加卡片、点击调起与系统刷新回归
- 🟡 **常驻速度通知**：上下行实时显示；运行中且“启用速度显示”开启时发布 Harmony ongoing 通知，
  每 3 秒按 `CGoQueryStats` 累计值差分刷新上传/下载速率，停止或关闭设置时取消
  （2026-06-18 代码完成，待真机通知权限与展示回归）
- ✅ **关于页更新检查**：对应 v2rayNG `UpdateCheckerManager`；
  About 页从 GitHub release API 拉取 tag/assets，比较当前版本 `1.1.0`，发现新版本时打开下载页/Release 页，失败时记录运行日志；`pref_check_update_pre_release` 等价开关可选择是否包含 pre-release

**v2rayNG 对照**：`UrlSchemeActivity`、`share2QRCode`、`WidgetProvider`/`QSTileService`/`shortcuts.xml`、`UpdateCheckerManager`。
**验收标准**：外部链接可一键导入；节点可生成二维码被另一台设备扫入。
**依赖**：M1（速度通知）；其余独立。

---

### M5 · 高级路由与云备份（进阶 · 可选）

**目标**：面向中高级用户的差异化能力。

**任务**
- 🟡 **负载均衡（Balancer）**：运行核心已完成，`policy-group` JSON 可生成，且已有普通节点可通过专门 UI 构建为策略组配置
  `routing.balancers`，支持 `leastPing/leastLoad/random/roundRobin` 与对应
  `observatory` / `burstObservatory`；路由规则可选择当前策略组目标；动态成员可按订阅分组和节点名正则在启动时展开
- 🟡 **策略组（PolicyGroup）**：静态成员 JSON 运行核心已完成；构建器会拒绝完整配置、嵌套高级节点和无效 outbound；添加节点页已有成员选择/策略选择/保存入口；从订阅按正则动态选成员已完成，真机组合场景待回归
- 🟡 **代理链（ProxyChain）**：运行核心已完成，`proxy-chain` JSON 导入后可生成多段 outbounds 并用 `sockopt.dialerProxy` 串联；添加节点页已有成员选择、顺序调整与保存入口
- ✅ **WebDAV 云备份/恢复**：BASIC 认证 + best-effort `MKCOL` 建目录 + 上传/下载 Hey ZIP 备份包（默认 `backups/backup_ng.zip`，内含 `hey_backup.json`，恢复兼容旧 JSON 包）；真服务兼容回归待补

**v2rayNG 对照**：`BalancerStrategyType`、`ServerGroupActivity`、`ServerProxyChainActivity`、
`WebDavManager`。
**验收标准**：策略组按延迟自动择优；WebDAV 备份可跨设备恢复。
**依赖**：M2（路由系统）、M3（订阅）。

---

## 四、协议与解析的并行点检（穿插各里程碑）

不单列里程碑，随手补齐：

- ✅ Reality 全参数（`spiderX`、`mldsa65Verify`/`pqv`）解析与下发：分享链接导入/导出、Clash.Meta 订阅解析和 NodeEdit Reality 表单均会保留后量子验签公钥（2026-06-18）
- ✅ `flow`（`xtls-rprx-vision` / `xtls-rprx-vision-udp443`）字段：分享链接导入导出保留，NodeEdit 手动编辑选项对齐 v2rayNG（2026-06-19）
- ✅ uTLS fingerprint（`fp`）：分享链接导入导出保留，NodeEdit 指纹选项对齐 v2rayNG `chrome/firefox/safari/ios/android/edge/360/qq/random/randomized`（2026-06-19）
- ✅ VMess QR TLS insecure：旧版 VMess JSON 分享里的 `insecure=1` 会导入为 `tlsSettings.allowInsecure`，导出再导入仍保留（2026-06-19）
- ✅ URL-style TLS allowInsecure 导出：VLESS/Trojan 等分享导出按 v2rayNG 同时写入 `insecure` 与 `allowInsecure` 兼容键，`0/1` 状态可 round-trip 保留（2026-06-19）
- ✅ URL-style userInfo 编码：Trojan/WireGuard/Hysteria2/HTTP 等导出按 v2rayNG 对 userInfo 做 URI 编码，密码/密钥含 `@`、`/`、`?`、`+`、`=` 时 round-trip 保留（2026-06-19）
- ✅ URL-style 空备注默认值：VLESS/VMess AEAD/Trojan/SS/SOCKS/WireGuard/Hysteria2 等分享链接缺少 fragment 时按 v2rayNG 使用 `none` 作为节点名（2026-06-19）
- ✅ 分享链接支持列表文案：解析失败提示、本地化文案和导入/扫码页说明已同步实际支持的 `https://`、`socks4://`、`socks5://` 与 `hy2://` 别名，避免支持能力和用户提示漂移（2026-06-19）
- ✅ finalMask（`fm`）：分享链接导入导出保留 `streamSettings.finalmask`，NodeEdit 可填写 FinalMask raw JSON（2026-06-19）
- ✅ TCP HTTP 头伪装：`type=tcp&headerType=http` 可导入导出，NodeEdit 手动编辑可选择 `none/http` 并写入 `tcpSettings.header.request`（2026-06-19）
- ✅ HTTPUpgrade / XHTTP 传输参数：`httpupgrade` host/path 导入导出保留，NodeEdit 可选择；XHTTP `mode/extra` 可手动填写并导入导出保留（2026-06-19）
- ✅ gRPC 传输模式：`mode=multi` 可导入导出为 `grpcSettings.multiMode`，NodeEdit 手动编辑可在 v2rayNG `gun/multi` 两种模式间选择（2026-06-19）
- ✅ KCP 传输参数：`type=kcp` 的 `headerType`/`seed`/`mtu`/`tti` 可导入导出，运行 outbound 生成 v2rayNG 风格 `kcpSettings` + `finalmask.udp`，NodeEdit 可选择 KCP header/seed/MTU/TTI（2026-06-19）
- ✅ SOCKS 分享认证：导出时按 v2rayNG 使用 `base64(user:pass)` 作为 userInfo，导入导出 round-trip 保留认证信息（2026-06-19）
- ✅ SOCKS scheme 别名：按 v2rayNG 支持 `socks4://` / `socks5://` 导入，统一归一为 Xray `socks` outbound；导出仍使用 `socks://` 主 scheme（2026-06-19）
- ✅ Shadowsocks legacy 尾斜杠兼容：整段 base64 旧格式导入允许 v2rayNG 正则支持的可选末尾 `/`，并覆盖 method 小写化与密码中冒号解析（2026-06-19）
- ✅ Hysteria2 端口跳跃（`mport`/`mportHopInt`）、`obfs`、证书 pin（`pinSHA256`）与带宽：分享链接解析和手动编辑器均已写入 outbound，导出 `mportHopInt` 时按 v2rayNG 规则规范化为不少于 5 秒的单值间隔，运行配置会生成 `finalmask.quicParams.brutalUp/brutalDown`、`udpHop` 与 `salamander` mask（2026-06-19；运行态仍待真机/内核验证）
- ✅ WireGuard `.conf` 文件整段解析（2026-06-18 已完成：`[Interface]`/`[Peer]` 文本或文件导入转为 Xray wireguard outbound）
- ✅ WireGuard/Hysteria2 手动编辑器：NodeEdit 已生成可校验 outbound，WG 支持 secret/public/pre-shared/reserved/MTU/IPv6 endpoint，HY2 支持 SNI/ALPN/insecure/obfs/mport/mportHopInt/pinSHA256/bandwidth，且 HY2 bandwidth/obfs/port-hop 会在启动配置中转为 v2rayNG 风格 `finalmask`（2026-06-19）
- ✅ SOCKS 端口/UDP/认证/动态端口：Settings 已可配置本地 SOCKS inbound，`localSocksEnabled` 按 v2rayNG `pref_enable_local_proxy` 默认开启，写入 `socks-in` 端口、UDP 与用户名/密码认证，并随代理共享监听 LAN；动态端口开启时连接前通过 `CGoGetFreePorts` 选择运行端口，失败回退用户设置端口（2026-06-19 补默认开启语义）
- ✅ 本地 DNS / FakeDNS 已生成 Xray `dns-out`、FakeDNS server 和 TUN 53 端口路由；remote/domestic DNS 已按 v2rayNG 规则生成 proxy/direct domain-bound servers、CN `expectIPs`、DNS 专用 proxy/direct 路由、block hosts 和内置 googleapis/Private DNS 默认 hosts（2026-06-19）

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
- [x] 真连接延迟测试：Settings 保存 `realPingConcurrency` 与 `delayTestUrl`；节点菜单提供 TCP 延迟和真连接测速两个入口，真连接批量测速按配置分批并发、通过 native `CGoPing` 访问目标 URL 并串行落盘（2026-06-19 补首页入口接线）
- [x] 删除配置确认：Settings 保存 `confirmRemove`，默认关闭；开启后单节点删除与订阅分组删除弹二次确认（2026-06-18）
- [x] 立即启动扫码：Settings 保存 `startScanImmediate`，默认关闭；开启后进入 Scanner 页自动拉起 ScanKit 相机扫码（2026-06-18）
- [x] 速度显示：Settings 保存 `speedEnabled`，默认关闭；开启后生成 metrics/stats/policy 并显示上传/下载，关闭时不启动 VPN stats 轮询（2026-06-18）
- [x] 语言跟随系统：Settings 保存 v2rayNG `pref_language=auto/en/zh`，默认 `auto`；`auto` 通过 Harmony 系统语言解析为中/英显示，设置页三段切换并补单测（2026-06-19）
- [x] UI 模式：Settings 保存 v2rayNG `uiModeNight=0/1/2`，应用启动/回前台/保存设置后切换 Harmony 跟随系统/浅色/深色 colorMode（2026-06-18）
- [x] 显示所有分组：Settings 保存 `groupAllDisplay`，节点页开启 All 虚拟分组并聚合所有订阅分组节点，搜索/测速/导出按聚合可见节点执行（2026-06-18）
- [x] 双列显示：Settings 保存 `doubleColumnDisplay`，默认关闭；开启后节点页以双列列表展示配置并保留选择/滑动操作（2026-06-18）
- [x] 当前连接信息测试网址：Settings 保存 `ipApiUrl`，默认 `https://api.ip.sb/geoip`；启动成功后经本地 HTTP 代理查询出口国家/IP 并写入运行日志（2026-06-18）
- [x] 二维码生成：节点详情页用 `@kit.ScanKit` `generateBarcode.createBarcode` 渲染分享链接 QR + 复制链接（2026-06-15）
- [x] URL Scheme / Want 深链导入：`hey://install-sub` / `hey://install-config?url=` 注册 scheme + `EntryAbility.onCreate/onNewWant` 暂存 + Index `onPageShow` 解析导入（2026-06-15）

> ✅ 2026-06-15 批 backlog 全部完成。后续可补充项：负载均衡/策略组/代理链编辑器（M5）、
> WebDAV 云备份；常驻速度通知已代码接线，待真机通知权限与真实流量回归。

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
| 2026-06-19 | M2 | ✅ routeOnly process 路由语义完成（`routeOnlyEnabled` 开启时写入 TUN sniffing `routeOnly` 并允许自定义规则输出 `process`；关闭时过滤 process-only 规则或移除 process 条件；补配置生成单测） |
| 2026-06-18 | M3 | ✅ 订阅分组重排（纯排序函数 + Store 持久化 + Subs 页滑动上移/下移 + 单测）；批量更新全部确认已落地 |
| 2026-06-18 | 协议点检 | ✅ WireGuard `.conf` 整段解析完成，支持粘贴/扫码/文件导入 `[Interface]` + `[Peer]` 配置并归一化为 Xray outbound |
| 2026-06-18 | M3 | ✅ 订阅级不安全 URL 开关（编辑页 `allowInsecureUrl` + 保存/更新 HTTP 校验 + 重定向校验 + 单测）；默认拒绝 `http://` 订阅，开启后允许 |
| 2026-06-18 | M3 | ✅ 当前分组删除全部配置（Nodes 菜单确认弹窗 + Store/Controller 清空 active group nodes + 删除数量日志）；补齐 v2rayNG `removeAllServer` 的日常批处理路径 |
| 2026-06-18 | M3 | ✅ 订阅自动更新设置与前台到期刷新（`autoUpdate`/`updateIntervalMinutes` + 1440/15 分钟规则 + 首页节流到期刷新 + 单测）；当时后台任务调度尚未接入 |
| 2026-06-18 | M3 | 🟡 订阅 WorkScheduler 后台调度接线（持久重复任务 + `SubscriptionUpdateWorkAbility` 到期刷新 + 增删改/首页同步注册 + 诊断日志 + 调度计划单测）；待真机触发回归 |
| 2026-06-18 | M3 | ✅ 运行中经由本地 HTTP 代理更新订阅（`appendHttpProxy` 设置 + `http-in` inbound 10808 + 订阅拉取 `usingProxy` 优先/直连回退 + 单测） |
| 2026-06-18 | M3 | ✅ 本地 HTTP 代理共享开关生效（`proxySharingEnabled` 开启时 `http-in.listen=0.0.0.0`，默认仍为 `127.0.0.1`，补配置生成单测） |
| 2026-06-18 | M0 补点 | ✅ VPN 接口 DNS 不再写死，`settings.vpnDns` 会规范化后写入 Harmony `VpnConfig.dnsAddresses`，空值回退 `1.1.1.1/8.8.8.8` |
| 2026-06-18 | M4 | ✅ 系统分享面板接入（批量导出文本 + 单节点分享链接走 `ohos.want.action.sendData`，失败回退剪贴板，并补分享 Want 单测） |
| 2026-06-18 | M4 | ✅ 完整自定义 Xray config 编辑完成（节点详情入口 + JSON 导入页编辑模式 + 手动节点原位更新 + 当前 profile 同步 + 单测覆盖命名解析） |
| 2026-06-18 | M0 补点 | ✅ TUN IPv6 设置接线完成（Settings `ipv6Enabled` 开关持久化 + VPN IPv6 client `/126` 地址 + `::/0` 默认路由 + `isIPv6Accepted`） |
| 2026-06-18 | M0 补点 | ✅ `preferIpv6` 继续贯通到生成的 Xray outbound：开启时写入 `sockopt.domainStrategy=UseIP` 与 `happyEyeballs.prioritizeIPv6/interleave`，并覆盖 fragment 共存单测 |
| 2026-06-18 | M0 补点 | ✅ VPN MTU 可配置完成（Settings `vpnMtu` 保存并规范化到 `1280..9000`，同步写入 Harmony `VpnConfig.mtu` 与 Xray `tun.settings.mtu`） |
| 2026-06-19 | M0 补点 | ✅ VPN MTU 默认值对齐 v2rayNG（默认从 1400 调整为 1500，Settings 初始值、缺省 TUN inbound 与无效输入回退均走 `DEFAULT_VPN_MTU`） |
| 2026-06-18 | M0 补点 | ✅ VPN 接口地址方案可配置完成（按 v2rayNG 7 组预设保存 `vpnInterfaceAddressIndex`，Harmony `VpnConfig.addresses` 使用对应 IPv4/IPv6 client 地址） |
| 2026-06-18 | M0 补点 | ✅ VPN 绕过 LAN 三态设置完成（保存 `vpnBypassLan=0/1/2`，绕过时用 v2rayNG 公网 IPv4 路由表；启用 IPv6 时追加 IPv6 `2000::/3`/`fc00::/18` 替代默认路由） |
| 2026-06-18 | M0 补点 | ✅ 本地 DNS / FakeDNS 接线完成（`localDnsEnabled` 生成 TUN 53 → `dns-out` 路由和 DNS outbound；`fakeDnsEnabled` 生成 `fakedns` server、顶层 `fakedns` 与 sniffing `fakedns`，`localDnsPort` 可保存） |
| 2026-06-18 | M1 | 🟡 Geo 文件校验/计数接线完成（`CGoReadGeoFiles`/`CGoCountGeoData` 导出 + native wrapper + Assets 页显示分类数/规则数）；待重建 `.so` + 真机复测 |
| 2026-06-18 | M1 | 🟡 Native 空闲端口接线完成（`CGoGetFreePorts` 导出 + native wrapper + 延迟测速/本地 SOCKS 动态端口，失败回退静态端口）；待重建 `.so` + 真机复测 |
| 2026-06-18 | M1 | 🟡 Native 分享转换接线完成（`CGoConvertShareLinksToXrayJson`/`CGOConvertXrayJsonToShareLinks` 导出 + native wrapper + 导入页批量/base64/Clash YAML 兜底）；待重建 `.so` + 真机复测 |
| 2026-06-18 | M4 | ✅ WireGuard/Hysteria2 手动编辑器校验完成（抽出 `ManualOutboundBuilder`，NodeEdit 复用，补 WG/HY2 outbound 生成单测）；运行态仍待真机/内核复测 |
| 2026-06-18 | M4 | ✅ 本地 SOCKS 代理设置完成（`localSocksEnabled`/端口/UDP/用户名/密码 + `socks-in` 生成 + LAN 共享监听 + 单测） |
| 2026-06-19 | M4 | ✅ 本地 SOCKS 默认开启对齐 v2rayNG（`pref_enable_local_proxy` 默认 true；默认设置生成 `socks-in`，关闭时不生成；补配置生成单测） |
| 2026-06-18 | M4 | ✅ 本地 SOCKS 动态端口完成（`localSocksDynamicPort` 设置 + 启动前 `CGoGetFreePorts` 选择运行端口 + 设置/端口选择单测）；待重建 `.so` + 真机复测 |
| 2026-06-18 | M4 | ✅ 传输高级设置完成（Settings 展开 mux 并发、XUDP 并发、UDP/443 策略、fragment packets/length/interval，日志级别改为 picker，并补 Settings draft 往返单测） |
| 2026-06-18 | M4 | ✅ DNS hosts 设置完成（Settings 保存 v2rayNG `domain:address,...` 输入，Xray 生成 `dns.hosts`；同时兼容 JSON object 输入并补配置生成单测） |
| 2026-06-18 | M4 | ✅ 出站域名预解析方式设置完成（Settings 保存 v2rayNG `pref_outbound_domain_resolve_method=0/1/2`，静态 DNS hosts 命中时可为 outbound 写入 `UseIP`/`happyEyeballs` 或直接替换服务器域名；补配置生成与 Settings 往返单测） |
| 2026-06-18 | M4 | ✅ 启动前 live DNS 预解析完成（连接启动前用 Harmony `connection.getAddressesByName` 解析 outbound 域名，合并到运行时 DNS hosts，不改持久化设置；普通节点、代理链、策略组均覆盖） |
| 2026-06-19 | M4 | ✅ DNS 分流配置增强完成（remote/domestic DNS 按自定义 proxy/direct/block 规则生成 domain-bound servers、CN `expectIPs`、DNS 模块 proxy/direct 路由、block hosts 与多上游 parallel query；补配置生成单测） |
| 2026-06-19 | M4 | ✅ DNS 默认 hosts 完成（内置 v2rayNG `googleapis.cn` 与 Android Private DNS 域名地址映射，用户 `dnsHosts` 后写覆盖默认值；补配置生成单测） |
| 2026-06-18 | M4 | ✅ 真连接延迟测试并发设置完成（`realPingConcurrency` 按 v2rayNG 默认 16 与 1..128 范围保存，首页批量测速按配置并发测量、串行保存结果，并补 Settings 往返/归一化单测） |
| 2026-06-19 | M4 | ✅ 首页真连接测速入口接线完成（Nodes 菜单新增“测试配置真连接”，走 `DelayTester.measureNodeOutbound`/native `CGoPing`，使用 Settings `delayTestUrl`；TCP 延迟菜单保留；补默认 URL 与策略组 probe URL 单测） |
| 2026-06-18 | M4 | ✅ 删除配置确认设置完成（`confirmRemove` 默认关闭，Settings 开关保存后控制单节点删除和订阅分组删除确认弹窗，并补 Settings 往返单测） |
| 2026-06-18 | M4 | ✅ 立即启动扫码设置完成（`startScanImmediate` 默认关闭，Settings 开关保存后控制 Scanner 页是否自动拉起 ScanKit，并修正此前无条件自动扫码行为） |
| 2026-06-18 | M4 | ✅ 速度显示设置完成（`speedEnabled` 默认关闭；开启后普通/代理链/策略组运行配置生成 metrics/stats/policy，首页/日志页显示上传下载并启动 VPN stats 轮询；关闭时隐藏流量显示并不生成统计段） |
| 2026-06-18 | M4 | ✅ UI 模式设置完成（`uiModeNight=0/1/2` 对齐 v2rayNG 跟随系统/浅色/深色；应用启动、回前台和 Settings 保存后应用 Harmony colorMode，并补 Settings 往返/归一化单测） |
| 2026-06-18 | M4 | ✅ 显示所有分组设置完成（`groupAllDisplay` 默认关闭；开启后节点页显示 All 虚拟分组，聚合所有订阅分组节点，并让搜索、批量测速和导出复用聚合可见节点；补 Settings 往返单测） |
| 2026-06-18 | M4 | ✅ 双列显示设置完成（`doubleColumnDisplay` 默认关闭；开启后节点页使用双列 `List` lanes 展示配置，并补 Settings 往返单测） |
| 2026-06-18 | M4 | ✅ 当前连接信息测试网址完成（`ipApiUrl` 默认 `https://api.ip.sb/geoip`；运行时经本地 HTTP 代理查询 IP API，解析 v2rayNG 兼容字段并追加当前连接日志；补 Settings 往返/解析单测） |
| 2026-06-18 | 协议点检 | ✅ Reality `pqv`/`mldsa65Verify` 完成（分享链接导入/导出、Clash.Meta 订阅解析与 NodeEdit Reality 表单均保留 ML-DSA-65 验签公钥；补解析/导出单测） |
| 2026-06-18 | 协议点检 | ✅ TLS/Reality `ech`/`pcs` 完成（分享链接导入/导出保留 ECH 配置与证书钉住 SHA256；TLS `insecure`、`allowInsecure`、`allow_insecure` 三种查询名统一解析；补解析/导出单测） |
| 2026-06-18 | 协议点检 | ✅ TLS/Reality `ech`/`pcs` 手动编辑完成（NodeEdit TLS/Reality 表单新增 ECH config list 与 pinned peer certificate SHA256，保存时写入 `tlsSettings`/`realitySettings`） |
| 2026-06-18 | M4 | ✅ 运行模式设置完成（`pref_mode` 保存 v2rayNG `VPN`/`Proxy only` 值；VPN 模式仍走 Harmony VPN Extension，Proxy-only 模式生成无 TUN 的本地 SOCKS 运行配置并直接调用 native Xray start/stop；补配置生成、动态端口和 Settings 往返单测） |
| 2026-06-18 | M0 补点 | ✅ IPv6 启用与优先 IPv6 拆分完成（新增 `ipv6Enabled` 对齐 v2rayNG `pref_ipv6_enabled`，VPN IPv6 地址/路由和 WireGuard IPv6 local address 受其控制；`preferIpv6` 仅保留 outbound Happy Eyeballs 语义） |
| 2026-06-18 | M5 | 🟡 代理链运行核心完成（`proxy-chain` configType + JSON 导入识别 + 多跳 outbounds `dialerProxy` 串联 + 单测）；真机组合场景待回归 |
| 2026-06-18 | M5 | 🟡 策略组/负载均衡运行核心完成（`policy-group` configType + JSON 导入识别 + `routing.balancers` + leastPing/leastLoad 观测配置 + 单测） |
| 2026-06-18 | M5 | 🟡 高级出站构建器完成（已有普通 outbound 节点 → `proxy-chain`/`policy-group` JSON + strategy 映射 + 嵌套/无效节点拒绝 + 单测） |
| 2026-06-18 | M5 | ✅ 高级出站成员选择 UI 完成（添加节点页入口 + 全分组普通节点选择 + 代理链顺序调整 + 策略组策略选择 + 保存为手动高级节点） |
| 2026-06-18 | M5 | ✅ 路由规则高级出站目标 UI 完成（规则编辑器按当前选中高级节点显示代理链/策略组目标，导入导出与运行时保留高级目标语义） |
| 2026-06-18 | M5 | ✅ 策略组订阅动态成员完成（创建策略组可启用动态成员、选择全部/指定订阅分组、输入节点名正则过滤，保存快照并在连接启动前按最新订阅重新展开） |
| 2026-06-18 | M5 | ✅ WebDAV 云备份/还原基础完成（Assets 页保存 WebDAV 配置，JSON 备份包上传/下载，Basic Auth + best-effort MKCOL + 单测） |
| 2026-06-18 | M5 | ✅ WebDAV ZIP 备份格式完成（默认 `backups/backup_ng.zip`，ZIP stored 条目内含 `hey_backup.json`，上传/下载走二进制，恢复兼容旧 JSON 备份 + 单测） |
| 2026-06-18 | M4 | ✅ 控制深链入口完成（manifest 注册 `hey://control`/`start`/`stop`/`toggle`/`switch`/`scan`，Index 处理 start/stop/toggle/scan，补解析单测）；桌面卡片/快捷方式 UI 仍待补 |
| 2026-06-18 | M4 | 🟡 常驻速度通知代码完成（`SpeedNotificationManager` 接 Harmony NotificationKit，运行中且 speedEnabled 开启时每 3 秒刷新速率/累计流量，停止或关闭设置时取消，补速率/节流文案单测）；待真机通知权限与通知中心展示回归 |
| 2026-06-18 | M4 | 🟡 桌面服务卡片基础入口完成（`ControlCardAbility` + `form_config` + 2×2 ArkTS 卡片，提供 toggle/start/stop/scan 四个 `FormLink` 控制深链，补卡片 URI 单测）；待真机添加卡片、点击调起与运行态动态刷新回归 |
| 2026-06-18 | M4 | 🟡 桌面服务卡片动态状态刷新代码完成（保存卡片 formId 与最近运行态，首页运行态变化同步状态文案、详情、主按钮动作并按 3 秒节流通过 `formProvider.updateForm` 刷新）；待真机添加卡片、点击调起与系统刷新回归 |
| 2026-06-18 | M4 | ✅ 关于页更新检查完成（About 页通过 GitHub latest release API 解析 tag/assets，比较当前版本 `1.1.0`，发现新版本时打开下载页/Release 页，失败写运行日志；补版本比较与 release 解析单测） |
| 2026-06-18 | M4 | ✅ 关于页预发布更新检查开关完成（保存 `pref_check_update_pre_release` 等价设置，开启后检查 GitHub releases 列表并允许 pre-release 版本命中；补 release 列表选择与 Settings 往返单测） |
| 2026-06-19 | M4 | ✅ 语言跟随系统完成（`pref_language=auto/en/zh` 三态、默认 `auto`，通过 Harmony `i18n.System.getSystemLanguage()` 解析系统语言，设置页三段切换，补语言归一化与解析单测） |
| 2026-06-19 | M3 | ✅ 分应用代理批处理完成（PerApp 页支持全选/清除/反选当前筛选列表，按 v2rayNG 剪贴板格式导入/导出 `bypass + package list`，默认模式对齐为代理选中应用，导入后自动启用分应用代理；补包名列表与 VPN 映射单测） |
| 2026-06-19 | M3 | ✅ 分应用自动选择完成（PerApp 页新增自动选择需代理应用，使用内置代理应用清单并保留 v2rayNG `com.google*` 强制匹配、WebView 排除和 bypass 补集语义；补 helper 单测） |
| 2026-06-19 | M4 | ✅ 订阅链接二维码/分享完成（订阅详情页生成订阅 URL QR，支持复制与系统分享；订阅分组左滑分享走 Harmony `sendData`，失败回退剪贴板；补分享 Want 单测） |
| 2026-06-19 | 协议点检 | ✅ `flow`/uTLS 指纹选项完成（NodeEdit 手动编辑补齐 `xtls-rprx-vision-udp443` 与 `ios/android/randomized` 指纹选项，分享链接导入导出保留这些值；补选项和 round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ VMess QR TLS insecure 完成（旧版 VMess JSON `insecure=1` 导入为 `tlsSettings.allowInsecure`，导出后再导入仍保留；补 round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ URL-style TLS allowInsecure 导出完成（VLESS/Trojan 等 TLS 分享导出同时写 `insecure` 与 `allowInsecure`，true/false 均按 v2rayNG `1/0` 输出；补 round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ URL-style userInfo 编码完成（Trojan/WireGuard/Hysteria2/HTTP 导出对密码、私钥和用户密码做 URI 编码，特殊字符不再截断分享链接；补 round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ URL-style 空备注默认值完成（分享链接缺少 fragment 时按 v2rayNG 将导入节点名设为 `none`，订阅导入同样保留；补解析与订阅单测） |
| 2026-06-19 | 协议点检 | ✅ 分享链接支持列表文案完成（解析器支持列表、失败提示、本地化与导入/扫码说明统一覆盖 `https://`、`socks4://`、`socks5://`、`hy2://`；补支持列表防漂移单测） |
| 2026-06-19 | 协议点检 | ✅ finalMask `fm` 完成（分享链接 `fm` raw JSON 导入为 `streamSettings.finalmask`，导出保留；NodeEdit 手动编辑可填写 FinalMask JSON；补 round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ TCP HTTP 头伪装完成（NodeEdit 可选择 v2rayNG `none/http`，保存 `tcpSettings.header.request`；分享链接 `headerType=http` host/path round-trip 保留） |
| 2026-06-19 | 协议点检 | ✅ HTTPUpgrade/XHTTP 传输参数完成（分享链接 `type=httpupgrade` 的 host/path 导出不再丢失，NodeEdit 可选择 httpupgrade；XHTTP `mode/extra` 可手动填写并 round-trip 保留；补传输选项与参数单测） |
| 2026-06-19 | 协议点检 | ✅ gRPC 传输模式完成（NodeEdit 可选择 v2rayNG `gun/multi`，保存时写入 `grpcSettings.multiMode`；分享链接 `mode=multi` round-trip 保留） |
| 2026-06-19 | 协议点检 | ✅ KCP 传输参数完成（分享链接 `type=kcp` 的 `headerType`/`seed`/`mtu`/`tti` 导入导出保留，运行 JSON 生成 `kcpSettings` 与 v2rayNG 风格 `finalmask.udp`，NodeEdit 可手动填写；补 KCP 参数与 VMess QR round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ SOCKS 分享认证导出完成（用户密码导出为 v2rayNG `base64(user:pass)` userInfo，导入导出 round-trip 保留认证信息） |
| 2026-06-19 | 协议点检 | ✅ SOCKS scheme 别名完成（`socks4://` / `socks5://` 订阅和手动分享导入归一为 `socks` outbound，导出使用 `socks://`；补解析/订阅单测） |
| 2026-06-19 | 协议点检 | ✅ Shadowsocks legacy 尾斜杠兼容完成（整段 base64 旧格式允许 v2rayNG 的 `host:port/` 写法，并补 method 小写化/密码冒号单测） |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 端口跳跃间隔完成（分享链接 `mportHopInt` 导入为 `portHoppingInterval`，导出时按 v2rayNG 规则规范化，NodeEdit 可填写端口跳跃间隔；补手动 builder 与 share round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 `pinSHA256` 完成（分享链接导入/导出保留 HY2 专属证书 pin，NodeEdit 手动编辑可填写并写入 outbound；补手动 builder 与 share round-trip 单测） |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 bandwidth/obfs/port-hop 运行配置完成（手动/订阅 HY2 节点启动前生成 `finalmask.quicParams` brutal 带宽、`udpHop` 和 `salamander` mask；补 runtime config 单测） |
| 2026-06-15 | 自查 | ✅ 字段一致性总扫：AppSettings/SettingsDraft 5 个构造点字段完整一致，SubscriptionGroup.filter 贯通，无需修改 |
| 2026-06-15 | 自查 | ✅ 深链/metrics 配置形状核对 Xray 官方一致；自查清单收尾（净修复：预检非阻断 + 清理未用导入） |
