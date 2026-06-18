# Hey VPN 路线图（对标 v2rayNG）

本文件记录 Hey 在 HarmonyOS Next 上对标 Android v2rayNG 的完成度评估与分阶段实施规划。
评估基于真实代码（截至 2026-06-18），而非声称状态。配套页面/功能对照见
[`v2rayng-feature-map.md`](v2rayng-feature-map.md)。

## 一、真实完成度评分

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| 应用骨架 / 导航 / i18n | ✅ 99% | 双语、分层清晰、路由完整，语言设置已支持 v2rayNG 风格 `auto` 跟随系统/中文/英文三态，UI 模式可按设置跟随系统/浅色/深色，About 页已接 GitHub release 更新检查，并支持 v2rayNG 风格 pre-release 检查开关 |
| 原生 TUN 数据通路 | ✅ 93% | 代码就位且**真机闭环验证通过（2026-06-15）**——TUN→Xray→出站→可上网；`ipv6Enabled` 控制 IPv6 地址/路由，`preferIpv6` 控制 outbound Happy Eyeballs，待真机回归 |
| 分享链接解析 | ✅ 91% | vless/vmess/trojan/ss/socks/http/wireguard/hy2 已覆盖，Reality `spx`/`pqv` 已按 v2rayNG 映射为 `spiderX`/`mldsa65Verify` 并可导入导出，WireGuard `.conf` 整段导入已支持；导入失败后可走 native 转换兜底支持 v2rayN 多行/base64 与 Clash.Meta YAML（待重建 `.so` 真机验证）；TUIC 在 v2rayNG 当前枚举中未启用且 Xray-core 官方配置不支持，暂不列为运行目标 |
| 订阅管理 | 🟡 95% | 多分组 + 旧版迁移 + 编辑/重排/批量更新全部 + 订阅级不安全 URL 开关 + 当前分组删除全部 + 自动更新设置/前台到期刷新 + 本地 HTTP 代理经由更新 + WorkScheduler 后台调度接线；待真机触发回归 |
| Xray 配置生成 | 🟡 89% | 普通节点生成 TUN/DNS/routing/HTTP 代理和本地 SOCKS 配置，速度显示开启时才生成 metrics/stats/policy；DNS hosts 支持 v2rayNG `domain:address,...` 格式写入 `dns.hosts`，并内置 v2rayNG `googleapis.cn` 与 Android Private DNS 默认 hosts，用户 hosts 可覆盖默认值；remote/domestic DNS 会按自定义 proxy/direct/block 规则生成 `domains`、`expectIPs`、DNS 专用路由和 block hosts，出站域名预解析方式 `0/1/2` 已持久化，并会在启动前用 Harmony 系统 DNS 补齐 live 解析结果，再按模式写入 DNS hosts/UseIP 或替换 outbound 域名；HTTP/SOCKS 代理支持局域网共享监听，SOCKS 支持启动前动态端口；完整自定义 Xray config 可校验后原样运行；代理链和策略组 JSON 可生成多跳/负载均衡 outbounds，添加节点页可从已有普通节点创建代理链/策略组，策略组支持按订阅分组与节点名正则动态成员，路由规则可选择当前高级出站目标 |
| 节点延迟测速 / 排序 | ✅ 84% | `CGoPing` 真测速 + 排序，测速 SOCKS inbound 优先使用 `CGoGetFreePorts` 动态端口；批量测速并发数已按 v2rayNG 设置接线；需真机验证 |
| 路由设置页 | ✅ 82% | 广告拦截、自定义规则、预设规则集导入/导出均已生效；自定义规则可选择当前高级出站目标；真机规则回归待补 |
| Geo 资产管理 | ✅ 93% | 下载 / 自定义 URL / 剪贴板备份还原 / WebDAV ZIP 云备份还原已实现，恢复兼容旧 JSON 包；Geo 文件 native 计数/校验已接线，待重建 `.so` 真机验证 |
| 分应用代理 | 🟡 70% | 开关、黑白名单、手动包名、应用枚举和 VPN 应用映射已接线；仍受平台可见性限制，待真机回归 |
| 设置页 | 🟡 93% | 核心项持久化并生效，`pref_mode` 已支持 VPN / Proxy only，本地 SOCKS 代理静态/动态端口、UDP、认证已写入运行配置；IPv6 启用与 IPv6 优先已按 v2rayNG 拆分；mux/XUDP/fragment 高级参数、fake DNS、DNS hosts、出站域名预解析方式（含启动前 live DNS 预解析）、速度显示、常驻速度通知、当前连接信息测试网址、语言跟随系统、UI 模式、显示所有分组、双列显示、删除配置确认、立即启动扫码与日志级别选择器已接线 |
| 扫码导入 | ✅ 82% | 粘贴导入和 ScanKit 相机扫码已接线；`startScanImmediate` 开启时进入扫码页自动拉起相机，待真机相机权限/机型回归 |
| 导出 / 分享 | ✅ 82% | 文本/文件导出、节点二维码与系统分享面板已完成；后续主要是真机分享目标兼容回归 |
| 平台集成 | 🟡 52% | Want / URL Scheme 深链导入已完成；控制深链支持 start/stop/toggle/scan，可作为 Tasker/快捷方式入口；常驻速度通知已接 Harmony NotificationKit；2×2 桌面服务卡片基础入口已接 FormExtensionAbility/FormLink，并已通过保存 formId + updateForm 同步运行态，待真机通知权限、卡片添加/点击与系统刷新回归 |

### Native 桥接现状

`libxray.so` 导出 13 个 CGo 函数，当前 `napi_init.cpp` 已接通 12 个：

- 已接通：`CGoRunXrayFromJSON`、`CGoStopXray`、`CGoPing`、`CGoSetTunFd`、
  `CGoQueryStats`（真实流量统计）、`CGoTestXray`（配置预检）、`CGoXrayVersion`、
  `CGoReadGeoFiles` / `CGoCountGeoData`（geo 校验/计数）、`CGoGetFreePorts`（动态空闲端口）、
  `CGoConvertShareLinksToXrayJson` / `CGOConvertXrayJsonToShareLinks`（分享文本 ⇄ Xray JSON 转换）
- **闲置**：`CGoRunXray`

> 当前预构建 `libxray.so` 仍需按更新后的 version-script 重建；重建前新增可选符号会优雅降级。

## 二、分阶段路线图

### 阶段 0：真机闭环验证 ✅ 已完成（2026-06-15）

- 真机安装 HAP，跑通 连接 → TUN → Xray → 出站 → 实际可上网 ✅
- 验证 `CGoSetTunFd` + Xray `tun` inbound 的真实转发 ✅

清单见 [`real-device-vpn-test.md`](real-device-vpn-test.md)。
**产出**：真机已验证可上网，阻塞项解除，主线推进至阶段 1（内核能力补全）。

### 阶段 1：补全 Native 内核能力（投入小、解锁多）

在 `napi_init.cpp` 接通闲置的 CGo 函数：

- `CGoQueryStats` → 真实上下行流量统计
- `CGoTestXray` → 连接前配置预检，减少启动失败
- `CGoXrayVersion` → About 页显示内核版本
- ✅ `CGoReadGeoFiles` / `CGoCountGeoData` → geo 文件校验与计数（2026-06-18 代码接线，待重建/真机）
- ✅ `CGoConvertShareLinksToXrayJson` / `CGOConvertXrayJsonToShareLinks` → 分享文本与 Xray JSON 互转；导入页已用 native 转换作为批量/base64/Clash YAML 兜底（2026-06-18 代码接线，待重建/真机）

**产出**：统计准确 + 配置可预检。

### 阶段 2：路由规则系统（核心差距）

- ✅ 让 Routing 页的「广告拦截」「自定义规则集」真正生效（2026-06-18 已完成自定义规则模型/编辑/下发）
- ✅ `XrayConfig.ets` 的 `buildRoutingRules` 扩展：多规则、ad-block
  （`geosite:category-ads-all` → block）、用户自定义 域名 / IP / 端口规则
- ✅ 新建规则编辑器（增删改 + 启停 + 上移/下移排序 + 持久化）
- ✅ 预设规则集导入/导出、规则锁定保留策略

**产出**：对齐 v2rayNG RoutingSettingActivity / RoutingEditActivity。

### 阶段 3：分应用代理

- 用鸿蒙 `bundleManager` 枚举已安装应用
- 选择列表 → 写入 `vpnConfig` 的 `acceptedApplications` / `refusedApplications`
- 持久化白 / 黑名单

**产出**：对齐 PerAppProxyActivity。

### 阶段 4：体验功能补全（多数可并行）

- ✅ 相机扫码（`@kit.ScanKit` scanBarcode）替代纯粘贴
- 二维码生成（节点分享）
- Reality `mldsa65Verify` / `pqv` 后量子验签参数导入导出（已完成）
- 完整自定义 Xray config 导入、编辑与原样运行（已完成）
- 自动订阅更新 WorkScheduler 真机触发回归（代码接线已完成）
- 运行中经由本地代理更新订阅（已完成）

### 阶段 5：平台集成（鸿蒙特性）

- ✅ Want / 深链导入（对应 v2rayNG UrlScheme）
- ✅ 控制深链入口：`hey://control?action=start|stop|toggle|scan` 与短 URI `hey://start`/`stop`/`toggle`/`scan`
- ✅ 开机自动连接设置：持久化 `pref_is_booted` 等价设置，并在 Harmony `AUTO_STARTUP` 启动原因下自动启动当前节点（受系统自启动权限/开关限制，待真机重启回归）
- 🟡 常驻速度通知：运行中且速度显示开启时发布 ongoing 通知，每 3 秒刷新上传/下载速率与累计流量（待真机通知权限/展示回归）
- 🟡 桌面快捷方式、服务卡片（widget）：2×2 服务卡片提供 toggle/start/stop/scan 四个控制入口，已接入运行态动态刷新（状态文案、详情与主按钮动作，按 3 秒节流），待真机添加、点击调起与系统刷新回归

## 三、依赖关系

```text
阶段0(真机验证) ──┬─→ 阶段1(内核) ──→ 阶段2(路由) ──→ 阶段3(分应用)
                  └─→ 阶段4(体验)   // 多数可与 1/2/3 并行
                                    阶段5(平台)   // 最后
```

## 四、进度记录

| 日期 | 阶段 | 变更 |
| --- | --- | --- |
| 2026-06-03 | — | 建立路线图，完成基于真实代码的完成度评估 |
| 2026-06-05 | — | 阶段规划由 [`development-plan.md`](development-plan.md) 取代（稳步推进版，含最新实测基线） |
| 2026-06-15 | 阶段 0 | ✅ 真机数据通路闭环验证通过；阻塞项解除 |
| 2026-06-18 | 阶段 2 | ✅ 自定义路由规则模型、Route 页编辑管理和 Xray `routing.rules` 下发完成 |
| 2026-06-18 | 阶段 2 | ✅ 预设规则集导入/导出与 locked 规则保留完成；路由规则系统主功能闭环，待真机验证 |
| 2026-06-18 | 阶段 4 | ✅ 订阅分组重排与持久化完成；批量更新全部确认已在订阅页落地 |
| 2026-06-18 | 阶段 4 | ✅ 订阅级不安全 URL 开关完成；默认拒绝 HTTP 订阅地址，按分组开启后允许 |
| 2026-06-18 | 阶段 4 | ✅ 当前分组删除全部配置完成；补齐 Nodes 菜单的删除全部/去重/清无效批处理组合 |
| 2026-06-18 | 阶段 4 | ✅ 订阅自动更新设置与前台到期刷新完成；当时后台任务调度尚未接入 |
| 2026-06-18 | 阶段 4 | 🟡 订阅 WorkScheduler 后台调度接线完成；按已开启自动更新的最短订阅间隔注册持久重复任务，后台唤醒时执行到期刷新，待真机触发回归 |
| 2026-06-18 | 阶段 4 | ✅ 运行中经由本地 HTTP 代理更新订阅完成；`appendHttpProxy` 生成 `http-in` 并让订阅拉取优先走代理、失败回退直连 |
| 2026-06-18 | 阶段 4 | ✅ 完整自定义 Xray config 导入与原样运行完成；手动节点/profile 记录 `configType`，导出/清无效兼容 full config |
| 2026-06-18 | 阶段 4 | ✅ 自定义配置文件选择导入完成；JSON 导入页支持 `.json`/`.txt`/`.conf` 文件读取后校验保存 |
| 2026-06-18 | 阶段 4 | ✅ 完整自定义 Xray config 编辑完成；节点详情可打开手动 custom/full 节点，编辑名称与 JSON，校验后更新原节点并同步当前 profile |
| 2026-06-18 | 阶段 4 | ✅ 节点配置文件导出完成；Export 页支持当前分组复制文本与保存 `.txt` 文件 |
| 2026-06-18 | 阶段 4 | ✅ WireGuard `.conf` 整段导入完成；`[Interface]`/`[Peer]` 文本会归一化为 Xray wireguard outbound |
| 2026-06-18 | 阶段 4 | ✅ 系统分享面板完成；Export 批量文本和节点详情单节点链接走 Harmony `sendData` 分享，失败回退剪贴板 |
| 2026-06-18 | 阶段 0 | ✅ TUN IPv6 设置接线完成；`ipv6Enabled` 持久化后生成 IPv6 TUN 地址与 `::/0` 默认路由 |
| 2026-06-18 | 阶段 0 | ✅ Xray IPv6 优先解析接线完成；`preferIpv6` 开启时生成 outbound `sockopt.happyEyeballs` |
| 2026-06-18 | 阶段 0 | ✅ VPN MTU 设置接线完成；`vpnMtu` 保存后同时应用到 Harmony `VpnConfig` 与 Xray TUN inbound |
| 2026-06-18 | 阶段 0 | ✅ VPN 接口地址方案完成；按 v2rayNG 7 组预设选择 TUN IPv4/IPv6 client 地址 |
| 2026-06-18 | 阶段 0 | ✅ VPN 绕过 LAN 完成；三态设置控制 Harmony VPN 默认路由或公网覆盖路由 |
| 2026-06-18 | 阶段 0 | ✅ 本地 DNS / FakeDNS 完成；开启后生成 TUN 53 → `dns-out` 路由、DNS outbound 与 FakeDNS 配置 |
| 2026-06-18 | 阶段 4 | ✅ 本地 HTTP 代理共享监听完成；`proxySharingEnabled` 开启时 `http-in` 监听 `0.0.0.0:10808` |
| 2026-06-18 | 阶段 1 | 🟡 Geo 文件校验/计数接线完成；`CGoReadGeoFiles`/`CGoCountGeoData` 已导出并在 Assets 页展示分类数/规则数，待重建 `.so` + 真机验证 |
| 2026-06-18 | 阶段 1 | 🟡 Native 空闲端口接线完成；延迟测速与本地 SOCKS 动态端口优先用 `CGoGetFreePorts` 获取运行端口，失败回退静态端口，待重建 `.so` + 真机验证 |
| 2026-06-18 | 阶段 1 | 🟡 Native 分享转换接线完成；导入失败后调用 `CGoConvertShareLinksToXrayJson` 解析 v2rayN 多行/base64 与 Clash.Meta YAML，并提取 outbounds 保存为手动节点，待重建 `.so` + 真机验证 |
| 2026-06-18 | 阶段 4 | ✅ WireGuard/Hysteria2 手动编辑器校验完成；NodeEdit 生成可校验 outbound，覆盖 WG IPv6 endpoint、reserved/MTU 与 HY2 obfs/mport/SNI/ALPN 单测 |
| 2026-06-18 | 阶段 4 | ✅ 本地 SOCKS 代理设置完成；Settings 可配置启用、端口、UDP、用户名/密码认证，Xray 生成 `socks-in` 并随代理共享监听 LAN |
| 2026-06-18 | 阶段 4 | ✅ 本地 SOCKS 动态端口完成；`localSocksDynamicPort` 开启后连接前通过 `CGoGetFreePorts` 写入运行端口，失败回退用户设置端口 |
| 2026-06-18 | 阶段 4 | ✅ 传输高级设置完成；Settings 可编辑 mux 并发、XUDP 并发、UDP/443 策略、fragment packets/length/interval，并将日志级别改为受控选择 |
| 2026-06-18 | 阶段 4 | ✅ DNS hosts 设置完成；Settings 可保存 v2rayNG `domain:address,...` 格式并生成 Xray `dns.hosts`，同时兼容 JSON object 输入 |
| 2026-06-18 | 阶段 4 | ✅ 出站域名预解析方式设置完成；Settings 保存 v2rayNG `pref_outbound_domain_resolve_method=0/1/2`，静态 DNS hosts 命中时可为 outbound 写入 `UseIP`/`happyEyeballs` 或直接替换服务器域名 |
| 2026-06-18 | 阶段 4 | ✅ 启动前 live DNS 预解析完成；普通节点、代理链和策略组在连接前通过 Harmony 系统 DNS 解析 outbound 域名，并把结果合并到运行时 DNS hosts 后按 `0/1/2` 模式生成配置 |
| 2026-06-19 | 阶段 4 | ✅ DNS 分流配置增强完成；remote/domestic DNS 按自定义路由规则生成 domain-bound servers、CN `expectIPs`、DNS 模块 proxy/direct 路由和 block hosts |
| 2026-06-19 | 阶段 4 | ✅ DNS 默认 hosts 完成；生成配置内置 v2rayNG `googleapis.cn` 与 Android Private DNS 域名地址映射，用户 DNS hosts 后写覆盖 |
| 2026-06-18 | 阶段 4 | ✅ 真连接延迟测试并发设置完成；Settings 保存 `realPingConcurrency`（默认 16、范围 1..128），首页批量测速按配置分批并发执行并串行保存结果 |
| 2026-06-18 | 阶段 4 | ✅ 删除配置确认设置完成；Settings 保存 `confirmRemove`（默认关闭），开启后单节点删除与订阅分组删除会弹二次确认 |
| 2026-06-18 | 阶段 4 | ✅ 立即启动扫码设置完成；Settings 保存 `startScanImmediate`（默认关闭），开启后进入 Scanner 页自动拉起 ScanKit 相机扫码 |
| 2026-06-18 | 阶段 4 | ✅ 速度显示设置完成；Settings 保存 `speedEnabled`（默认关闭），开启后生成 metrics/stats/policy 并展示上传/下载，关闭时不启动统计轮询 |
| 2026-06-18 | 阶段 4 | ✅ UI 模式设置完成；Settings 保存 `uiModeNight=0/1/2`（跟随系统/浅色/深色），应用启动、回前台和保存设置后同步 Harmony colorMode |
| 2026-06-18 | 阶段 4 | ✅ 显示所有分组设置完成；Settings 保存 `groupAllDisplay`（默认关闭），开启后节点页增加 All 虚拟分组并聚合所有订阅分组节点，搜索/测速/导出按聚合可见节点执行 |
| 2026-06-18 | 阶段 4 | ✅ 双列显示设置完成；Settings 保存 `doubleColumnDisplay`（默认关闭），开启后节点页按双列列表展示配置并保留选择/滑动操作 |
| 2026-06-18 | 阶段 4 | ✅ 当前连接信息测试网址完成；Settings 保存 `ipApiUrl`（默认 `https://api.ip.sb/geoip`），VPN 启动成功且本地 HTTP 代理可用时经代理查询出口国家/IP 并写入运行日志 |
| 2026-06-18 | 阶段 4 | ✅ Reality `pqv`/`mldsa65Verify` 参数完成；分享链接、Clash.Meta 订阅、节点导出和 NodeEdit Reality 表单均保留后量子验签公钥 |
| 2026-06-18 | 阶段 4 | ✅ TLS/Reality `ech`/`pcs` 参数完成；分享链接导入导出保留 ECH 与证书钉住参数，并兼容 `insecure`/`allowInsecure`/`allow_insecure` 三种不安全 TLS 查询名 |
| 2026-06-18 | 阶段 4 | ✅ TLS/Reality `ech`/`pcs` 手动编辑完成；NodeEdit 可填写 ECH config list 与 pinned peer certificate SHA256，并写入 `tlsSettings`/`realitySettings` |
| 2026-06-18 | 阶段 4 | ✅ 运行模式设置完成；Settings 保存 v2rayNG `pref_mode` 值 `VPN`/`Proxy only`，Proxy-only 启动时跳过 Harmony VPN Extension，直接运行 native Xray 并强制提供本地 SOCKS 代理入口 |
| 2026-06-18 | 阶段 0 | ✅ IPv6 启用与优先 IPv6 拆分完成；`ipv6Enabled` 控制 VPN IPv6 地址/路由与 WireGuard IPv6 local address，`preferIpv6` 仅控制 outbound Happy Eyeballs |
| 2026-06-18 | 阶段 5 | 🟡 代理链运行核心完成；JSON 导入支持 `proxy-chain`，运行时生成多跳 outbounds 并通过 `sockopt.dialerProxy` 串联，真机组合场景待回归 |
| 2026-06-18 | 阶段 5 | 🟡 策略组/负载均衡运行核心完成；JSON 导入支持 `policy-group`，运行时生成 `routing.balancers`、leastPing/leastLoad 观测配置与默认 balancer 路由 |
| 2026-06-18 | 阶段 5 | 🟡 高级出站构建器完成；可从已有普通 outbound 节点生成 `proxy-chain`/`policy-group` JSON，并拒绝完整配置、嵌套高级节点和无效节点 |
| 2026-06-18 | 阶段 5 | ✅ 高级出站成员选择 UI 完成；添加节点页可创建代理链/策略组，支持全分组普通节点选择、顺序调整、策略选择并保存为手动高级节点 |
| 2026-06-18 | 阶段 5 | ✅ 路由规则高级出站目标 UI 完成；规则编辑器按当前高级节点显示代理链/策略组目标，导入导出与运行时生成保留高级目标语义 |
| 2026-06-18 | 阶段 5 | ✅ 策略组订阅动态成员完成；创建策略组可选择全部/指定订阅分组与节点名正则过滤，保存 `policyGroupSubscriptionId`/`policyGroupFilter` 快照并在启动时按最新订阅重新展开 |
| 2026-06-18 | 阶段 5 | ✅ WebDAV 云备份/还原基础完成；Assets 页可保存 WebDAV 配置并上传/下载 Hey JSON 备份包，支持 Basic Auth 与 best-effort MKCOL |
| 2026-06-18 | 阶段 5 | ✅ WebDAV ZIP 备份格式完成；默认 `backups/backup_ng.zip`，ZIP 内含 `hey_backup.json`，上传/下载走二进制并兼容旧 JSON 恢复 |
| 2026-06-18 | 阶段 5 | ✅ 控制深链入口完成；注册 `hey://control?action=start|stop|toggle|scan` 与短 URI，首页可通过外部 Want 启停/切换连接或打开扫码页，对齐 v2rayNG Tasker/shortcuts/QS tile 的基础控制能力 |
| 2026-06-18 | 阶段 5 | 🟡 常驻速度通知代码完成；运行中且速度显示开启时通过 NotificationKit 发布 ongoing 通知，按 3 秒节流刷新上传/下载速率和累计流量，停止或关闭设置时取消，待真机回归 |
| 2026-06-18 | 阶段 5 | 🟡 桌面服务卡片基础入口完成；注册 `ControlCardAbility` 与 `form_config`，2×2 ArkTS 卡片用 FormLink 调起 toggle/start/stop/scan 控制深链，待真机添加卡片、点击调起和动态状态刷新回归 |
| 2026-06-18 | 阶段 5 | 🟡 桌面服务卡片动态状态刷新代码完成；保存卡片 formId 与最近运行态，首页运行态变化同步状态文案、详情、主按钮动作并按 3 秒节流通过 `formProvider.updateForm` 刷新，待真机添加卡片、点击调起和系统刷新回归 |
| 2026-06-18 | 阶段 5 | ✅ 关于页更新检查完成；About 页通过 GitHub latest release API 解析 tag/assets，比较当前版本 `1.1.0`，发现新版本时打开下载页/Release 页，失败写运行日志 |
| 2026-06-18 | 阶段 5 | ✅ 关于页预发布更新检查开关完成；About 页保存 `pref_check_update_pre_release` 等价设置，开启后检查 GitHub releases 列表并允许 pre-release 命中 |
| 2026-06-19 | 阶段 4 | ✅ 语言跟随系统完成；Settings 保存 v2rayNG `pref_language=auto/en/zh`，默认 `auto`，通过 Harmony 系统语言解析为中/英显示并补单测 |
