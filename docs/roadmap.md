# Hey VPN 路线图（对标 v2rayNG）

本文件记录 Hey 在 HarmonyOS Next 上对标 Android v2rayNG 的完成度评估与分阶段实施规划。
评估基于真实代码（截至 2026-06-20），而非声称状态。配套页面/功能对照见
[`v2rayng-feature-map.md`](v2rayng-feature-map.md)。

## 一、真实完成度评分

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| 应用骨架 / 导航 / i18n | ✅ 99% | 双语、分层清晰、路由完整，语言设置已支持 v2rayNG `pref_language=auto/en/zh-rCN/zh-rTW/vi/ru/fa/ar/bn/bqi-rIR` 完整枚举，`auto` 跟随系统，非中英语言值保留并回退英文显示；共享页头标题/状态会随异步语言与状态刷新，避免深链进入二级页时出现混合语言；首页统计标签、无订阅引导空态、节点页当前分组空态、添加节点页主入口、JSON 导入页、手动节点编辑页字段/保存/校验提示、订阅编辑页字段、占位符、校验与保存文案已跟随当前语言；分应用代理页过滤策略、应用列表、搜索/手动添加、关闭态和预置应用标签已跟随当前语言；路由设置页流量模式、routeOnly、域名策略、预置规则集和预设详情已跟随当前语言；Assets 页快捷操作、内置 Geo、自定义资源入口/列表和相关 toast 已跟随当前语言；导出页标题、按钮、复制/文件/分享提示和 Nodes 批量导出结果已跟随当前语言并避免异步加载混合语言；运行时 VPN/Proxy-only 启停失败、超时/未确认和状态卡片消息已跟随当前语言；About 页分区标题与链接失败提示已跟随当前语言；UI 模式可按设置跟随系统/浅色/深色，配置/扫码/订阅剪贴板导入提示已跟随当前语言，About 页已接 GitHub release 更新检查，About/Settings 页共用 v2rayNG 风格 pre-release 检查开关 |
| 原生 TUN 数据通路 | ✅ 94% | 代码就位且**真机闭环验证通过（2026-06-15）**——TUN→Xray→出站→可上网；`ipv6Enabled` 控制 IPv6 地址/路由，`preferIpv6` 控制 outbound Happy Eyeballs，VPN MTU 默认值已对齐 v2rayNG 为 1500，待真机回归 |
| 分享链接解析 | ✅ 99% | vless/vmess/trojan/ss/socks/http/wireguard/hy2 已覆盖，VLESS `flow` 含 `xtls-rprx-vision-udp443`、VLESS manual encryption 按 v2rayNG `et_security` 自由文本编辑和回填、uTLS `fp` 含 `ios/android/randomized`、VMess QR `insecure` 按 v2rayNG 导入导出 `1/0`、VMess URL-style user security 默认 `auto` 且 `security=tls/reality` 仅作为传输层安全配置、URL-style TLS `insecure`/`allowInsecure` 兼容键导出、URL-style userInfo 编码、URL-style/WireGuard/Hysteria2 分享导出会按 v2rayNG `FmtBase.toUri` 将 IDN server/endpoint host 转 punycode、空 fragment 默认 `none` 节点名、finalMask `fm`、TCP `headerType=http/none`、裸 VLESS/Trojan outbound 导出会补齐普通 TCP 默认 `security/type/headerType` query、KCP `headerType/seed/mtu/tti`、gRPC `mode=multi`、SOCKS 去 padding `base64(user:pass)` 认证/无认证 `Og` 导出与 `socks4://` / `socks5://` 导入别名、Shadowsocks legacy base64 兼容尾斜杠与密码冒号、SIP002 `obfs=http` plugin 可导入且导出不回写 `plugin`、WireGuard reserved 缺省值 `0,0,0` 与 MTU 缺省值 `1420`、Hysteria2 `security=none/tls`/`insecure=1/0`/`mportHopInt`/`pinSHA256`、HTTPUpgrade host/path、XHTTP `mode/extra` 均可导入导出并在手动编辑器选择/填写，且 XHTTP mode 按 v2rayNG `auto/packet-up/stream-up/stream-one` 枚举兜底非法值；Hysteria2 security 会在运行配置中控制是否生成 TLS settings，bandwidth/obfs/port-hop 会生成 v2rayNG 风格 `finalmask.quicParams`、`udpHop` 和 `salamander` mask；Reality `spx`/`pqv` 已按 v2rayNG 映射为 `spiderX`/`mldsa65Verify` 并可导入导出，WireGuard `.conf` 整段导入已支持；导入失败后可走 native 转换兜底支持 v2rayN 多行/base64 与 Clash.Meta YAML，`libxray.so` 已重建并导出分享转换符号，待真机验证；TUIC 在 v2rayNG 当前枚举中未启用且 Xray-core 官方配置不支持，暂不列为运行目标 |
| 订阅管理 | 🟡 99% | 多分组 + 旧版迁移 + 编辑/重排/批量更新全部 + 订阅级不安全 URL 开关 + 当前/All 可见范围批量删除/去重/测速失败清理 + 自动更新设置/前台到期刷新 + 本地 HTTP 代理经由更新 + v2rayNG 风格每订阅独立 WorkScheduler 后台调度 + 订阅链接二维码/系统分享 + `prevProfile`/`nextProfile` 备注字段编辑/持久化；订阅列表页摘要/空态/本地节点数量/未更新状态与批量/自动更新结果提示已跟随当前语言；订阅详情页页头摘要、链接区、更新按钮、节点列表与空态已跟随当前语言；订阅编辑页已覆盖 v2rayNG `SubEditActivity` 字段、占位符、校验与保存按钮的本地化；订阅 URL 剪贴板粘贴提示已接入 i18n；订阅抓取支持 v2rayNG 风格 URL 内嵌 `user:pass@host` Basic Auth，并会按 `HttpUtil.toIdnUrl` 等价逻辑将非 ASCII 域名转换为 punycode 后请求；订阅刷新已按 v2rayNG 多级匹配保留当前选中节点；待真机触发回归 |
| Xray 配置生成 | 🟡 94% | 普通节点生成 TUN/DNS/routing/HTTP 代理和本地 SOCKS 配置，本地 SOCKS 按 v2rayNG `pref_enable_local_proxy` 默认开启、默认端口 10808，且关闭时不生成 `socks-in`；追加 HTTP 代理仅在 VPN 模式暴露，并跟随本地代理总开关，关闭本地代理或切换 Proxy-only 时不再单独生成 `http-in`；速度显示开启时才生成 metrics/stats/policy；DNS hosts 支持 v2rayNG `domain:address,...` 格式写入 `dns.hosts`，并内置 v2rayNG `googleapis.cn` 与 Android Private DNS 默认 hosts，用户 hosts 可覆盖默认值；remote/domestic DNS 会按自定义 proxy/direct/block 规则生成 `domains`、`expectIPs`、DNS 专用路由和 block hosts，FakeDNS sniffing 按 v2rayNG 仅跟随 FakeDNS 开关，顶层 `fakedns` 与 DNS FakeDNS server 仍要求本地 DNS + FakeDNS；TLS/Reality 节点运行配置会按 v2rayNG 从传输 host/authority 或服务器域名补齐空 SNI，配置证书 pin 时禁用 `allowInsecure`；Hysteria2 运行配置会按 v2rayNG 归一为 Xray core 的 `protocol=hysteria`、`settings.address/port/version` 与 `streamSettings.hysteriaSettings.auth`，并按 security 保留 TLS/pin 或省略 `tlsSettings`，同时保留 finalmask；Browser Dialer 保存为 WS/XHTTP profile 元数据，普通启动/延迟测试/完整配置运行输出会剥离该字段；出站域名预解析方式 `0/1/2` 已持久化，并会在启动前用 Harmony 系统 DNS 补齐 live 解析结果，再按模式写入 DNS hosts/UseIP 或替换 outbound 域名，IDN host 会按 v2rayNG `CoreOutboundBuilder.getServerAddress` 使用 punycode 参与预解析并输出到普通启动/测速配置；全局 Mux 按 v2rayNG 规则跳过 Shadowsocks/SOCKS/HTTP/Trojan/WireGuard/Hysteria2/XHTTP，保存 `-1..1024` 的 Mux/XUDP 并发并保留 `-1/0` 写入运行配置，全局关闭或协议跳过时会把导入节点已有 mux 显式置为关闭，且 VLESS flow 节点使用 `concurrency=-1`；全局 Fragment 按 v2rayNG 生成 TLS/Reality `finalmask.tcp/udp`，并跳过已有 finalmask 与代理链 dialerProxy；`routeOnly` 会按 v2rayNG 语义写入 TUN sniffing（普通 sniffing/FakeDNS 均关闭时仍保留 `enabled=false` + `routeOnly=true`），process 规则输出还会对齐 v2rayNG `canUseProcessRouting`，仅在 `routeOnly` 开启且未启用 Hev TUN 时将包名解析为 Harmony app UID（`__unknown_app__` 映射 `-1`）；生成 Xray routing 时会按 v2rayNG 将 `geoip:cn/private` 改写为 `geoip-only-cn-private.dat` ext 引用，DNS `expectIPs` 与设置展示保留原值；HTTP/SOCKS 代理支持局域网共享监听，SOCKS 支持启动前动态端口；完整自定义 Xray config 可校验后原样运行，且 `routing.rules.process` 仅在可使用 process routing 且包名成功解析时按 v2rayNG 替换为 UID；代理链和策略组 JSON 可生成多跳/负载均衡 outbounds，添加节点页可从已有普通节点创建代理链/策略组，策略组支持按订阅分组与节点名正则动态成员且过滤匹配大小写不敏感，路由规则可选择当前高级出站目标 |
| 节点列表 / 延迟测速 / 排序 | ✅ 95% | 节点列表与详情页使用 v2rayNG `AngConfigManager.generateDescription` 同款脱敏地址描述，并纳入节点搜索；普通订阅分组内支持按 v2rayNG 列表拖拽重排语义上移/下移节点并持久化顺序，All 聚合分组保持只读排序语义；节点菜单同时提供 TCP 延迟、v2rayNG 风格真连接测速、手动按测试结果排序和“定位所选配置”，定位会切到选中节点所在订阅分组并滚动到节点位置；TCP 延迟复用结构化 outbound endpoint 解析；真连接测速走 `CGoPing` + 独立 SOCKS 测试 inbound，优先使用 `CGoGetFreePorts` 动态端口，测速配置会按 v2rayNG 移除 outbound mux，并按 `delayTestUrl` 设置访问目标 URL；代理链批量真连接测速会保留多跳 `dialerProxy`，策略组批量真连接测速会通过 `balancer` 路由 SOCKS 测试入口；完整自定义配置测速会注入临时 SOCKS inbound、剥离原 inbounds/DNS/FakeDNS/stats/policy/mux，并路由到 `proxy` 或首个可用 outbound；普通/高级/完整配置启动成功后均会追加 v2rayNG 单次连接延迟日志，主 URL 失败时重试备用 `https://www.google.com/generate_204`，成功后再查询出口 IP；批量测速并发数已按 v2rayNG 设置接线，手动/自动排序与删除失败节点均按订阅分组与 All 虚拟分组语义落盘；native core 真实设备回归仍需继续补齐 |
| 路由设置页 | ✅ 84% | 广告拦截、自定义规则、预设规则集导入/导出均已生效，预设内容补齐 v2rayNG 中国白名单/黑名单公共 DNS IP/域名规则，规则集支持 v2rayNG 风格剪贴板与二维码 JSON 导入；路由域名策略按 v2rayNG `AsIs/IPIfNonMatch/IPOnDemand` 三值归一化后保存并写入 Xray；流量模式说明、`routeOnly` 文案、域名策略说明、预置规则集标题和预设详情弹窗均已跟随当前语言；`routeOnly` 控制 sniffing routeOnly，process 规则输出还需符合 v2rayNG `canUseProcessRouting`（Hev TUN 关闭时才转换包名 UID）；运行配置生成时将路由 IP 匹配里的 `geoip:cn/private` 改写为 v2rayNG 同款 ext 引用；自定义规则可选择当前高级出站目标；真机规则回归待补 |
| Geo 资产管理 | ✅ 98% | 下载 / 自定义 URL / 本地 `.dat` 导入 / 资源 URL 二维码导入 / 自定义资源名称唯一性校验 / 本地文件资源隐藏编辑入口（按 `url == "file"` 行为）/ 内置下载已包含 v2rayNG 强制更新的 `geoip-only-cn-private.dat`，用于支撑 `geoip:cn/private` ext 路由，下载源选择补齐 v2rayNG 的 Loyalsoldier / Russia / Iran 三组规则源；资源下载会在本地 HTTP 代理暴露时先走 `127.0.0.1:10809`，失败后直连兜底，未暴露代理时保持直连；Assets 页主视图和用户资源列表可见文案已跟随当前语言并避免异步加载混合语言；Geo 文件 native 计数/校验已接线，`libxray.so` 已重建并导出 Geo 符号，待真机验证 |
| 分应用代理 | 🟡 83% | 开关、黑白名单、手动包名、应用枚举、批量全选/清除/反选、自动选中需代理应用、剪贴板导入导出和 VPN 应用映射已接线；自动选择会先拉取 v2rayNG `androidpackagenamelist` 远程列表，失败时回退内置列表，并保留 `com.google*` 强制匹配/WebView 排除；默认模式对齐 v2rayNG 为“代理选中的应用”，空列表仍阻断自身包名防回路；页面过滤策略、应用列表、搜索/手动添加、关闭态和预置应用标签已跟随当前语言；仍受平台可见性限制，待真机回归 |
| 设置页 | 🟡 96% | 核心项持久化并生效，`pref_mode` 已支持 VPN / Proxy only，本地 SOCKS 代理按 v2rayNG 默认开启，静态/动态端口、UDP、认证已写入运行配置；VPN DNS 空/未设置时按 v2rayNG `AppConfig.DNS_VPN` 只回退 `1.1.1.1`；Hev TUN 三项偏好（启用、日志级别、读写超时）按 v2rayNG 默认值保存，并在开启时保持本地 SOCKS 开启，Harmony 运行时仍使用 Xray TUN；设置保存与旧数据读取会按 v2rayNG 依赖门禁清理无效 FakeDNS、追加 HTTP 代理与 LAN 共享代理状态；IPv6 启用与 IPv6 优先已按 v2rayNG 拆分；允许 LAN 连接会切换本地代理监听并在启动成功后按 v2rayNG 给出可信网络警告；mux/XUDP/fragment 高级参数、fake DNS、DNS hosts、出站域名预解析方式（含启动前 live DNS 预解析）、速度显示、常驻速度通知、当前连接信息测试网址、完整语言枚举、UI 模式、pre-release 更新检查、显示所有分组、双列显示、删除配置确认、立即启动扫码与日志级别选择器已接线；运行中保存设置/路由/分应用或切换当前节点后会按 v2rayNG `SettingsChangeManager` 语义返回首页自动重启服务 |
| 扫码导入 | ✅ 88% | 粘贴导入、ScanKit 相机扫码与 v2rayNG `select_photo` 等价的相册图片二维码导入已接线；相册入口通过 Harmony Photo Picker 选择图片并用 ScanKit `detectBarcode.decode` 解码后复用同一导入链路；剪贴板读取不再声明受限 Harmony `READ_PASTEBOARD` 权限，普通调试签名安装不被 ACL 拦截，粘贴成功/失败/空内容提示已跟随当前语言；扫码页页头与内容在深链冷启动后均跟随当前语言刷新；扫码页在单链接解析失败后会复用 native 转换兜底，可导入 v2rayN 多行/base64 与 Clash.Meta YAML 文本/二维码；`startScanImmediate` 开启时进入扫码页自动拉起相机，待真机相机权限/机型回归 |
| 导出 / 分享 | ✅ 87% | 文本/文件导出、节点二维码、订阅链接二维码与系统分享面板已完成；批量导出已按 v2rayNG `shareNonCustomConfigsToClipboard` 只输出可分享普通节点并跳过自定义/高级/无效配置；Export 页复制文本、导出文件、分享入口和 Nodes 批量导出剪贴板成功/失败提示均已跟随当前语言；节点详情已支持 v2rayNG `shareFullContent2Clipboard` 等价的完整运行配置复制；后续主要是真机分享目标兼容回归 |
| 平台集成 | 🟡 60% | Want / URL Scheme 深链导入已完成，并按 v2rayNG 处理 `install-sub`/`install-config` 外层 fragment 名称兜底；外部应用 `sendData/text/plain` 分享配置导入已接线，复用订阅、单节点与 native 批量兜底导入路径，且首页会监听 EntryAbility 写入的 pending 外部意图，支持应用已在前台时继续消费热启动 deep link / share text；控制深链支持 start/stop/toggle/scan，可作为 Tasker/自动化入口，且 start/toggle 已支持 `guid`/`nodeId`/`id` 指定节点后启动，也接受 flat Tasker `tasker_extra_bundle_switch/guid` 参数，对齐 v2rayNG Tasker `switch + guid`；声明式桌面快捷方式已通过 `shortcuts_config` 暴露开关、启动、停止和扫码四个入口；Logcat 页已支持搜索、复制全部、分享全部、单条复制与清空；常驻速度通知已接 Harmony NotificationKit；2×2 桌面服务卡片基础入口已接 FormExtensionAbility/FormLink，并已通过保存 formId + updateForm 同步运行态，待真机通知权限、快捷方式/卡片添加点击与系统刷新回归 |

### Native 桥接现状

当前打包的 `libxray.so` 导出 12 个 CGo 函数，`napi_init.cpp` 已全部接通：

- 已接通：`CGoRunXrayFromJSON`、`CGoStopXray`、`CGoPing`、`CGoSetTunFd`、
  `CGoQueryStats`（真实流量统计）、`CGoTestXray`（配置预检）、`CGoXrayVersion`（已导出，About 消费因模拟器 crash 先安全降级）、
  `CGoReadGeoFiles` / `CGoCountGeoData`（geo 校验/计数）、`CGoGetFreePorts`（动态空闲端口）、
  `CGoConvertShareLinksToXrayJson` / `CGOConvertXrayJsonToShareLinks`（分享文本 ⇄ Xray JSON 转换）
- 上游旧入口 `CGoRunXray` 不作为 Hey 运行目标；Hey 使用 `CGoRunXrayFromJSON` 直接传入配置 JSON。

> 当前预构建 `libxray.so` 已按更新后的 version-script 重建；`llvm-nm -D` 已确认 12 个 CGo 符号均导出。新增 native 能力仍需真机回归。

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
- `CGoXrayVersion` → About 页显示内核版本（当前模拟器调用会触发 native SIGSEGV，About 先安全降级，待 native 复测/修复）
- ✅ `CGoReadGeoFiles` / `CGoCountGeoData` → geo 文件校验与计数（2026-06-18 代码接线，2026-06-19 `.so` 重建导出，待真机）
- ✅ `CGoConvertShareLinksToXrayJson` / `CGOConvertXrayJsonToShareLinks` → 分享文本与 Xray JSON 互转；导入页与扫码页已用 native 转换作为批量/base64/Clash YAML 兜底（2026-06-18/19 代码接线，2026-06-19 `.so` 重建导出，待真机）

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
- 对齐 v2rayNG 分应用批处理：全选、反选、自动选中需代理应用、剪贴板导入/导出包名列表

**产出**：对齐 PerAppProxyActivity。

### 阶段 4：体验功能补全（多数可并行）

- ✅ 相机扫码（`@kit.ScanKit` scanBarcode）替代纯粘贴
- ✅ 相册图片二维码导入（v2rayNG `select_photo` 等价路径）
- 二维码生成（节点/订阅分享）
- Reality `mldsa65Verify` / `pqv` 后量子验签参数导入导出（已完成）
- 完整自定义 Xray config 导入、编辑与原样运行（已完成）
- 自动订阅更新 WorkScheduler 真机触发回归（代码接线已完成）
- 运行中经由本地代理更新订阅（已完成）

### 阶段 5：平台集成（鸿蒙特性）

- ✅ Want / 深链导入（对应 v2rayNG UrlScheme）
- ✅ 控制深链入口：`hey://control?action=start|stop|toggle|scan` 与短 URI `hey://start`/`stop`/`toggle`/`scan`；start/toggle 可携带 `guid`/`nodeId`/`id` 指定节点，`guid=Default` 保持当前节点；冷启动和应用前台热启动均会消费 pending deep link
- ✅ 开机自动连接设置：持久化 `pref_is_booted` 等价设置，并在 Harmony `AUTO_STARTUP` 启动原因下自动启动当前节点（受系统自启动权限/开关限制，待真机重启回归）
- 🟡 常驻速度通知：运行中且速度显示开启时发布 ongoing 通知，每 3 秒刷新上传/下载速率与累计流量（待真机通知权限/展示回归）
- 🟡 桌面快捷方式、服务卡片（widget）：`shortcuts_config` 声明开关/启动/停止/扫码四个系统快捷方式，2×2 服务卡片提供 toggle/start/stop/scan 四个控制入口并接入运行态动态刷新（状态文案、详情与主按钮动作，按 3 秒节流），待真机添加、点击调起与系统刷新回归

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
| 2026-06-19 | 阶段 2 | ✅ 路由预设公共 DNS 规则对齐；中国白名单补齐公共 DNS IP 直连规则，中国黑名单补齐海外公共 DNS IP 与 `domain:yandex.net` |
| 2026-06-19 | 阶段 2 | ✅ 路由规则集二维码导入完成；Route 页新增 v2rayNG `import_rulesets_from_qrcode` 等价入口，扫码后确认并按规则数组 JSON 导入，保留 locked 规则 |
| 2026-06-19 | 阶段 2 | ✅ routeOnly process 路由语义完成；开启时写入 TUN sniffing `routeOnly` 并输出自定义规则 `process`，关闭时过滤 process-only 规则或移除 process 条件 |
| 2026-06-19 | 阶段 2 | ✅ 路由 GeoIP ext 规则完成；生成 Xray routing 时将 `geoip:cn/private` 改写为 `ext:geoip-only-cn-private.dat:cn/private`，DNS `expectIPs` 与设置展示保留原值 |
| 2026-06-19 | 阶段 2 | ✅ 路由 process UID 完成；普通自定义规则启动前将 process 包名解析为 Harmony app UID，`__unknown_app__` 映射 `-1`，完整 custom config 仅在解析成功时替换 |
| 2026-06-20 | 阶段 2 | ✅ process routing Hev 门槛对齐 v2rayNG；`canUseProcessRouting` 现在要求 `routeOnly` 开启且 Hev TUN 关闭，普通规则和完整 custom config 的 `process` UID 转换都复用同一判断 |
| 2026-06-20 | 阶段 4 | ✅ Settings 依赖门禁对齐 v2rayNG；关闭本地 DNS 会清理 FakeDNS，关闭本地代理会清理追加 HTTP 代理与 LAN 共享代理，Hev 强制本地代理时保留可用状态 |
| 2026-06-20 | 阶段 4 | ✅ 追加 HTTP 代理模式边界对齐 v2rayNG；`appendHttpProxy` 只在 VPN 模式生成 `http-in`/代理端口，Proxy-only 保留本地 SOCKS 入口并不暴露 HTTP 代理 |
| 2026-06-19 | 阶段 4 | ✅ FakeDNS sniffing 边界完成；sniffing 的 `fakedns` 仅跟随 FakeDNS 开关，顶层 `fakedns` 与 DNS FakeDNS server 仍要求本地 DNS + FakeDNS |
| 2026-06-18 | 阶段 4 | ✅ 订阅分组重排与持久化完成；批量更新全部确认已在订阅页落地 |
| 2026-06-18 | 阶段 4 | ✅ 订阅级不安全 URL 开关完成；默认拒绝 HTTP 订阅地址，按分组开启后允许 |
| 2026-06-18 | 阶段 4 | ✅ 当前分组删除全部配置完成；补齐 Nodes 菜单的删除全部/去重/清无效批处理组合 |
| 2026-06-19 | 阶段 3 | ✅ All 分组批处理语义完成；单节点删除、删除全部、去重、删除测速失败节点按当前可见节点跨订阅分组执行，测速后自动排序/删除失败节点按 v2rayNG 订阅分组语义保存 |
| 2026-06-19 | 阶段 3 | ✅ 手动按测试结果排序完成；节点菜单新增 v2rayNG `sort_by_test_results` 等价入口，按当前订阅分组或 All 虚拟分组分别排序并落盘 |
| 2026-06-20 | 阶段 3 | ✅ 节点列表搜索语义完成；Nodes 搜索按 v2rayNG 先执行大小写不敏感正则，非法正则退回字面量匹配，并支持普通 outbound server 地址命中 |
| 2026-06-20 | 阶段 3 | ✅ 节点地址描述完成；首页列表与节点详情按 v2rayNG `generateDescription` 显示 `addrPart : port` 脱敏端点，搜索同步匹配该描述，TCP 测速复用结构化端点解析 |
| 2026-06-20 | 阶段 3 | ✅ 节点顺序重排完成；普通订阅分组节点滑动操作新增上移/下移，按 v2rayNG `swapServer` 语义持久化当前分组 server 顺序，All 聚合分组不写入跨分组顺序 |
| 2026-06-20 | 阶段 3 | ✅ 定位所选配置完成；Nodes 菜单会按 v2rayNG 切到选中节点所在订阅分组并滚动到过滤后的节点位置，搜索隐藏时给出提示 |
| 2026-06-18 | 阶段 4 | ✅ 订阅自动更新设置与前台到期刷新完成；当时后台任务调度尚未接入 |
| 2026-06-18 | 阶段 4 | 🟡 订阅 WorkScheduler 后台调度接线完成；当时按已开启自动更新的最短订阅间隔注册统一持久重复任务，后台唤醒时执行到期刷新，待真机触发回归 |
| 2026-06-20 | 阶段 4 | ✅ 订阅后台 per-subscription 调度完成；按 v2rayNG `SubscriptionUpdater` 为每个自动更新订阅注册独立持久 WorkScheduler 任务，参数携带 groupId，后台唤醒时只刷新目标订阅并保留旧全量 due 扫描兜底 |
| 2026-06-18 | 阶段 4 | ✅ 运行中经由本地 HTTP 代理更新订阅完成；`appendHttpProxy` 在 VPN 模式生成 `http-in` 并让订阅拉取优先走代理、失败回退直连 |
| 2026-06-20 | 阶段 4 | ✅ 订阅内嵌 Basic Auth 完成；抓取 `https://user:pass@host/sub` 时按 v2rayNG 解码 userInfo 并写入 `Authorization: Basic ...` |
| 2026-06-20 | 阶段 4 | ✅ 订阅 IDN URL 完成；抓取订阅前按 v2rayNG `HttpUtil.toIdnUrl` 语义仅将 URL host 转 punycode，保留 Basic Auth 与路径原文 |
| 2026-06-20 | 阶段 4 | ✅ 订阅前/后置 Profile 字段完成；`prevProfile`/`nextProfile` 持久化并在订阅编辑页输入/回填，复制和批量节点操作保留字段 |
| 2026-06-20 | 阶段 4 | ✅ 分享/运行 IDN host 完成；URL-style 分享导出与普通启动/测速配置按 v2rayNG 将 server/endpoint host 转 punycode，DNS hosts 支持原文或 punycode key 命中 |
| 2026-06-20 | 协议点检 | ✅ VLESS encryption 手动编辑完成；NodeEdit 按 v2rayNG `et_security` 改为自由文本输入，默认 `none`，已有手动节点任意 encryption 可回填保留 |
| 2026-06-18 | 阶段 4 | ✅ 完整自定义 Xray config 导入与原样运行完成；手动节点/profile 记录 `configType`，导出/清无效兼容 full config |
| 2026-06-18 | 阶段 4 | ✅ 自定义配置文件选择导入完成；JSON 导入页支持 `.json`/`.txt`/`.conf` 文件读取后校验保存 |
| 2026-06-18 | 阶段 4 | ✅ 完整自定义 Xray config 编辑完成；节点详情可打开手动 custom/full 节点，编辑名称与 JSON，校验后更新原节点并同步当前 profile |
| 2026-06-18 | 阶段 4 | ✅ 节点配置文件导出完成；Export 页支持当前分组复制文本与保存 `.txt` 文件 |
| 2026-06-18 | 阶段 4 | ✅ WireGuard `.conf` 整段导入完成；`[Interface]`/`[Peer]` 文本会归一化为 Xray wireguard outbound |
| 2026-06-18 | 阶段 4 | ✅ 系统分享面板完成；Export 批量文本和节点详情单节点链接走 Harmony `sendData` 分享，失败回退剪贴板 |
| 2026-06-19 | 阶段 4 | ✅ 剪贴板导入安装兼容修正；移除受限 `ohos.permission.READ_PASTEBOARD` 声明和运行时授权请求，保留配置、订阅、路由规则、分应用、资源导入等入口在读取失败时的提示 |
| 2026-06-18 | 阶段 0 | ✅ TUN IPv6 设置接线完成；`ipv6Enabled` 持久化后生成 IPv6 TUN 地址与 `::/0` 默认路由 |
| 2026-06-18 | 阶段 0 | ✅ Xray IPv6 优先解析接线完成；`preferIpv6` 开启时生成 outbound `sockopt.happyEyeballs` |
| 2026-06-18 | 阶段 0 | ✅ VPN MTU 设置接线完成；`vpnMtu` 保存后同时应用到 Harmony `VpnConfig` 与 Xray TUN inbound |
| 2026-06-19 | 阶段 0 | ✅ VPN MTU 默认值对齐 v2rayNG；`DEFAULT_VPN_MTU` 与 Settings 初始值改为 1500，缺省 TUN inbound 生成 `mtu=1500` |
| 2026-06-18 | 阶段 0 | ✅ VPN 接口地址方案完成；按 v2rayNG 7 组预设选择 TUN IPv4/IPv6 client 地址 |
| 2026-06-18 | 阶段 0 | ✅ VPN 绕过 LAN 完成；三态设置控制 Harmony VPN 默认路由或公网覆盖路由 |
| 2026-06-18 | 阶段 0 | ✅ 本地 DNS / FakeDNS 完成；开启后生成 TUN 53 → `dns-out` 路由、DNS outbound 与 FakeDNS 配置 |
| 2026-06-18 | 阶段 4 | ✅ 本地 HTTP 代理共享监听完成；`proxySharingEnabled` 开启时 `http-in` 监听 `0.0.0.0:10809` |
| 2026-06-18 | 阶段 1 | 🟡 Geo 文件校验/计数接线完成；`CGoReadGeoFiles`/`CGoCountGeoData` 已导出并在 Assets 页展示分类数/规则数，`.so` 已重建，待真机验证 |
| 2026-06-18 | 阶段 1 | 🟡 Native 空闲端口接线完成；延迟测速与本地 SOCKS 动态端口优先用 `CGoGetFreePorts` 获取运行端口，失败回退静态端口，`.so` 已重建，待真机验证 |
| 2026-06-18 | 阶段 1 | 🟡 Native 分享转换接线完成；导入失败后调用 `CGoConvertShareLinksToXrayJson` 解析 v2rayN 多行/base64 与 Clash.Meta YAML，并提取 outbounds 保存为手动节点，`.so` 已重建，待真机验证 |
| 2026-06-19 | 阶段 1 | ✅ `libxray.so` 重建完成；补齐 OHOS 构建脚本的 Android API level stub 与 Go 1.23+ `-checklinkname=0`，新预构建库已导出 12 个 CGo 符号且均已接线 |
| 2026-06-18 | 阶段 4 | ✅ WireGuard/Hysteria2 手动编辑器校验完成；NodeEdit 生成可校验 outbound，覆盖 WG IPv6 endpoint、reserved/MTU 与 HY2 obfs/mport/SNI/h3 默认 ALPN 单测 |
| 2026-06-18 | 阶段 4 | ✅ 本地 SOCKS 代理设置完成；Settings 可配置启用、端口、UDP、用户名/密码认证，Xray 生成 `socks-in` 并随代理共享监听 LAN |
| 2026-06-19 | 阶段 4 | ✅ 本地 SOCKS 默认开启与端口对齐 v2rayNG；`localSocksEnabled` 新默认值为 true，默认端口 10808，默认配置会生成 `socks-in`，关闭后仍可移除本地 SOCKS 入口 |
| 2026-06-20 | 阶段 4 | ✅ Hev TUN 设置偏好对齐 v2rayNG；`pref_use_hev_tunnel_v2` 默认开启，`pref_hev_tunnel_loglevel` 限定 `error/warn/info/debug`，`pref_hev_tunnel_rw_timeout_v2` 保存 `tcp,udp` 秒数，并在开启 Hev 时保持本地 SOCKS 开启（Harmony 运行时仍使用 Xray TUN） |
| 2026-06-20 | 阶段 0 | ✅ VPN DNS 默认值对齐 v2rayNG；`vpnDns` 空/未设置时 Harmony VPN DNS 只回退 `1.1.1.1`，显式多 DNS 输入继续 trim、去重后保留 |
| 2026-06-20 | 阶段 4 | ✅ Proxy sharing 启动警告完成；允许来自局域网连接时，启动成功后按 v2rayNG 提醒用户确认当前网络可信 |
| 2026-06-18 | 阶段 4 | ✅ 本地 SOCKS 动态端口完成；`localSocksDynamicPort` 开启后连接前通过 `CGoGetFreePorts` 写入运行端口，失败回退用户设置端口 |
| 2026-06-18 | 阶段 4 | ✅ 传输高级设置完成；Settings 可编辑 mux 并发、XUDP 并发、UDP/443 策略、fragment packets/length/interval，并将日志级别改为受控选择 |
| 2026-06-19 | 阶段 4 | ✅ Mux 并发范围对齐完成；Mux/XUDP 并发保存范围改为 v2rayNG `-1..1024`，运行配置保留 `-1/0` |
| 2026-06-19 | 阶段 4 | ✅ Mux 禁用语义对齐完成；全局 Mux 关闭或协议不适用时，导入节点已有 mux 会按 v2rayNG 显式写为 `enabled=false`、`concurrency=-1` |
| 2026-06-18 | 阶段 4 | ✅ DNS hosts 设置完成；Settings 可保存 v2rayNG `domain:address,...` 格式并生成 Xray `dns.hosts`，同时兼容 JSON object 输入 |
| 2026-06-18 | 阶段 4 | ✅ 出站域名预解析方式设置完成；Settings 保存 v2rayNG `pref_outbound_domain_resolve_method=0/1/2`，静态 DNS hosts 命中时可为 outbound 写入 `UseIP`/`happyEyeballs` 或直接替换服务器域名 |
| 2026-06-18 | 阶段 4 | ✅ 启动前 live DNS 预解析完成；普通节点、代理链和策略组在连接前通过 Harmony 系统 DNS 解析 outbound 域名，并把结果合并到运行时 DNS hosts 后按 `0/1/2` 模式生成配置 |
| 2026-06-19 | 阶段 4 | ✅ DNS 分流配置增强完成；remote/domestic DNS 按自定义路由规则生成 domain-bound servers、CN `expectIPs`、DNS 模块 proxy/direct 路由和 block hosts |
| 2026-06-19 | 阶段 4 | ✅ DNS 默认 hosts 完成；生成配置内置 v2rayNG `googleapis.cn` 与 Android Private DNS 域名地址映射，用户 DNS hosts 后写覆盖 |
| 2026-06-18 | 阶段 4 | ✅ 真连接延迟测试并发设置完成；Settings 保存 `realPingConcurrency`（默认 16、范围 1..128），首页批量测速按配置分批并发执行并串行保存结果 |
| 2026-06-19 | 阶段 4 | ✅ 首页真连接测速入口接线完成；节点菜单新增“测试配置真连接”，批量测速走 native `CGoPing`、使用 `delayTestUrl` 目标 URL，保留 TCP 延迟菜单用于端口连通诊断 |
| 2026-06-19 | 阶段 4 | ✅ 真实延迟测速配置瘦身完成；测速配置按 v2rayNG 移除导入 outbound 自带 mux，避免测速路径受 mux 影响 |
| 2026-06-20 | 阶段 4 | ✅ 运行态连接延迟备用 URL 完成；普通 outbound 启动成功后记录当前连接延迟，按 v2rayNG 先测 `delayTestUrl`、失败再测 `https://www.google.com/generate_204`，成功后继续查询出口 IP |
| 2026-06-20 | 阶段 4 | ✅ 高级节点真连接测速配置完成；代理链测速配置保留多跳 `dialerProxy`，策略组测速配置通过 `balancer` 路由测试 SOCKS inbound，并继续按 v2rayNG 移除 outbound mux |
| 2026-06-20 | 阶段 4 | ✅ 完整自定义真连接测速配置完成；full custom 测速会生成独立 speedtest 配置，注入临时 SOCKS inbound，清理原 inbounds/DNS/FakeDNS/stats/policy/mux，并将运行态连接延迟放开到 ordinary/proxy-chain/policy-group/full |
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
| 2026-06-19 | 阶段 5 | ✅ 高级出站编辑回填完成；节点详情可重新打开手动代理链/策略组，预填成员顺序、策略和动态订阅过滤条件，并原位保存更新 |
| 2026-06-18 | 阶段 5 | ✅ 策略组订阅动态成员完成；创建策略组可选择全部/指定订阅分组与节点名正则过滤，保存 `policyGroupSubscriptionId`/`policyGroupFilter` 快照并在启动时按最新订阅重新展开，过滤匹配按 v2rayNG 搜索体验大小写不敏感 |
| 2026-06-20 | 阶段 5 | 🟡 备份能力从当前复刻范围剔除（无云服务器）：ZIP/WebDAV/剪贴板备份实现均下线，后续仅在有稳定云端目标时重新立项 |
| 2026-06-18 | 阶段 5 | ✅ 控制深链入口完成；注册 `hey://control?action=start|stop|toggle|scan` 与短 URI，首页可通过外部 Want 启停/切换连接或打开扫码页，对齐 v2rayNG Tasker/shortcuts/QS tile 的基础控制能力 |
| 2026-06-20 | 阶段 5 | ✅ 控制深链热启动消费完成；首页通过 `@StorageLink` 监听 EntryAbility 写入的 pending deep link/share text，应用已在前台时再次收到 `hey://scan` 等 Want 也会立即消费 |
| 2026-06-19 | 阶段 5 | ✅ 深链 fragment 名称兜底完成；`install-sub`/`install-config` 解析时外层 URI fragment 会在内层 URL 无 fragment 时作为名称补入，内层名称优先保留 |
| 2026-06-20 | 阶段 5 | ✅ 声明式桌面快捷方式完成；`EntryAbility` 通过 `ohos.ability.shortcuts` 绑定 `shortcuts_config`，开关/启动/停止/扫码四个快捷方式复用现有控制深链参数解析 |
| 2026-06-20 | 阶段 5 | ✅ Tasker 指定节点控制完成；控制深链和快捷方式参数支持 `guid`/`nodeId`/`id` 目标节点，也接受 `tasker_extra_bundle_switch/guid` 参数，start/toggle 会先选择目标节点再启动，`guid=Default` 保持当前节点 |
| 2026-06-20 | 阶段 4 | ✅ 共享页头响应式刷新完成；`PageHeader` 标题/摘要/状态改为响应式属性，扫码页深链冷启动后标题与内容语言一致（模拟器布局验证 `Scanner`，无旧中文标题残留） |
| 2026-06-20 | 阶段 4 | ✅ 首页统计标签响应式刷新完成；`Duration/Upload/Download` 改为在统计单元内部按当前语言翻译，模拟器英文首页布局验证 `Duration` 且无旧 `时长` 残留 |
| 2026-06-20 | 阶段 4 | ✅ 添加节点页主入口本地化完成；链接/扫码导入、手动协议列表、高级配置、JSON 配置入口和导入结果 toast 均走 i18n，模拟器英文布局验证 `Scan & link import`、`Create proxy chain` 且无旧中文入口残留 |
| 2026-06-20 | 阶段 4 | ✅ JSON 导入页本地化完成；粘贴/选择文件/清除、占位符、说明、校验状态、文件读取和导入/保存错误均走 i18n，模拟器英文布局验证 `Choose file`、`Note: you can import` 且无旧中文按钮/说明残留 |
| 2026-06-20 | 阶段 4 | ✅ 订阅详情页本地化完成；页头节点数、订阅链接分组、获取并更新按钮、节点列表分组和空态均走 i18n，模拟器英文布局验证 `Subscription URL`、`Update nodes`、`Node list` 且无旧中文文案残留 |
| 2026-06-20 | 阶段 4 | ✅ 订阅编辑页本地化完成；`SubEditActivity` 对应名称、URL、不安全链接、自动更新、User-Agent、过滤、前/后置 Profile 与保存/校验文案均跟随当前语言 |
| 2026-06-20 | 阶段 4 | ✅ 订阅列表页本地化完成；订阅分组页摘要、空态、本地节点/更新时间文案和批量/自动更新 toast 均走 i18n，模拟器验证英文页头为 `1 subscription group` 且无旧中文摘要残留 |
| 2026-06-20 | 阶段 4 | ✅ About 页本地化补齐；资源更新、技术规格、社区开发者分区标题和打开链接失败提示均走 i18n，模拟器英文布局验证分区/条目同语种、无旧中文残留，且进入 About 不再触发 `CGoXrayVersion` native crash |
| 2026-06-20 | 阶段 4 | ✅ 路由设置页本地化补齐；流量模式说明、routeOnly、域名策略、预置规则集和预设详情弹窗均走 i18n，模拟器英文布局验证规则模式与预置区域无旧中文残留 |
| 2026-06-20 | 阶段 4 | ✅ Assets 页本地化补齐；快捷操作、内置 Geo 资源、自定义资源入口/列表、下载/导入/删除/保存 toast 均走 i18n，并用加载门禁修复异步语言混合，模拟器英文主屏/下半屏/用户资源列表验证无旧中文残留 |
| 2026-06-20 | 阶段 4 | ✅ Export 页本地化补齐；导出页加载门禁、复制/文件/分享按钮、复制失败提示和 Nodes 批量导出剪贴板日志均走 i18n，模拟器英文布局验证无旧中文导出按钮/提示残留 |
| 2026-06-20 | 阶段 4 | ✅ 首页/节点空态本地化补齐；无订阅引导、当前分组无节点标题/说明/更新按钮均走 i18n，模拟器英文空分组布局验证 `No nodes in this group` 且无旧中文空态残留 |
| 2026-06-20 | 阶段 4 | ✅ 手动节点编辑页本地化补齐；NodeEdit 标题、分区、基础/认证/传输/TLS/Reality/WG/HY2 字段、保存按钮和校验/保存提示均走 i18n，并修复异步语言加载后字段行不刷新的问题，模拟器英文 VLESS 页验证 `Node name`、`Save node config` 且无旧中文字段残留 |
| 2026-06-20 | 阶段 4 | ✅ 运行时错误提示本地化补齐；VPN 启停超时/未确认、Proxy-only 启停失败与缺运行配置、状态卡片 Proxy-only 运行消息均走统一本地化，模拟器英文启动失败验证 `Failed to start VPN: VPN start timed out...` 且无旧中文错误残留 |
| 2026-06-20 | 阶段 4 | ✅ 手动/高级节点编辑错误本地化补齐；`ManualOutboundEditState`/`AdvancedOutboundBuilder` 的不支持协议、缺少 settings、节点配置解析失败、高级节点配置解析失败四类错误经 `localizeCoreMessage` 走 i18n，NodeEdit/AdvancedOutbound 展示侧统一本地化，补解析失败与映射单测，模拟器英文 VLESS 手动编辑页验证字段全英、无旧中文残留 |
| 2026-06-20 | 阶段 4 | ✅ 设置页实时语言切换刷新补齐；修复 ArkUI 私有 `@Builder` 值传递冻结导致的语言切换不刷新，Settings hub 菜单与通用偏好页改为传 key 内部 `this.t()` 翻译、`SettingOption` 动态取值经 `settingOptionValue(action)` 解析，模拟器实时中↔英切换验证 hub 菜单与偏好页标题/取值即时刷新、无需冷启动、无旧语言残留 |
| 2026-06-18 | 阶段 5 | 🟡 常驻速度通知代码完成；运行中且速度显示开启时通过 NotificationKit 发布 ongoing 通知，按 3 秒节流刷新上传/下载速率和累计流量，停止或关闭设置时取消，待真机回归 |
| 2026-06-18 | 阶段 5 | 🟡 桌面服务卡片基础入口完成；注册 `ControlCardAbility` 与 `form_config`，2×2 ArkTS 卡片用 FormLink 调起 toggle/start/stop/scan 控制深链，待真机添加卡片、点击调起和动态状态刷新回归 |
| 2026-06-18 | 阶段 5 | 🟡 桌面服务卡片动态状态刷新代码完成；保存卡片 formId 与最近运行态，首页运行态变化同步状态文案、详情、主按钮动作并按 3 秒节流通过 `formProvider.updateForm` 刷新，待真机添加卡片、点击调起和系统刷新回归 |
| 2026-06-18 | 阶段 5 | ✅ 关于页更新检查完成；About 页通过 GitHub latest release API 解析 tag/assets，比较当前版本 `1.1.0`，发现新版本时打开下载页/Release 页，失败写运行日志 |
| 2026-06-18 | 阶段 5 | ✅ 关于页预发布更新检查开关完成；About 页保存 `pref_check_update_pre_release` 等价设置，开启后检查 GitHub releases 列表并允许 pre-release 命中 |
| 2026-06-19 | 阶段 4 | ✅ pre-release 更新检查设置页入口完成；Settings 页新增 v2rayNG `pref_check_update_pre_release` 等价开关，与 About 页共用同一设置 |
| 2026-06-20 | 阶段 4 | ✅ v2rayNG 语言枚举完成；Settings 保存 `pref_language=auto/en/zh-rCN/zh-rTW/vi/ru/fa/ar/bn/bqi-rIR`，默认 `auto`，通过 Harmony 系统语言解析为 v2rayNG 语言码，旧 `zh`/`zh-Hans` 迁移到 `zh-rCN`，非中英语言值保留并回退英文显示 |
| 2026-06-19 | 阶段 3 | ✅ 分应用代理批处理完成；PerApp 页支持全选/清除/反选当前筛选列表，按 v2rayNG 剪贴板格式导入/导出 `bypass + package list`，默认“代理选中的应用”，导入后自动启用分应用代理 |
| 2026-06-19 | 阶段 3 | ✅ 分应用自动选择完成；PerApp 页新增“自动选择代理应用”，按内置代理应用清单和 v2rayNG `com.google*` 强制匹配规则选择当前筛选列表，bypass 模式选择补集 |
| 2026-06-20 | 阶段 3 | ✅ 分应用代理页本地化补齐；过滤策略、应用列表摘要、搜索/手动添加、关闭态、预置应用标签和相关日志均走 i18n，模拟器英文布局验证关闭态/列表态/手动添加区无旧中文残留 |
| 2026-06-19 | 阶段 3 | ✅ 分应用自动列表来源对齐 v2rayNG；自动选择先拉取 `2dust/androidpackagenamelist` 远程 `proxy.txt`，直连失败可经本地 HTTP 代理重试，空内容/失败回退内置列表；顺手修正 About 页 v2rayNG source 链接 |
| 2026-06-19 | 阶段 4 | ✅ 订阅链接分享完成；订阅详情页可生成订阅 URL 二维码并复制/系统分享，订阅分组左滑分享走 Harmony 分享面板并回退剪贴板 |
| 2026-06-19 | 协议点检 | ✅ `flow`/uTLS 指纹选项完成；NodeEdit 手动编辑补齐 `xtls-rprx-vision-udp443` 与 `ios/android/randomized`，分享链接导入导出 round-trip 保留 |
| 2026-06-19 | 协议点检 | ✅ VMess QR TLS insecure 完成；旧版 VMess JSON `insecure=1` 导入为 `tlsSettings.allowInsecure`，导出再导入保留 |
| 2026-06-19 | 协议点检 | ✅ VMess QR insecure 显式 false 导出完成；旧版 VMess JSON 导出在 TLS 且 `allowInsecure=false` 时按 v2rayNG 写入 `"insecure":"0"` |
| 2026-06-19 | 协议点检 | ✅ VMess URL-style security 分层完成；标准 URI 解析时 user security 保持 `auto`，`security=tls` 仅进入传输层 |
| 2026-06-19 | 协议点检 | ✅ VMess 手动 security 选项完成；NodeEdit 按 v2rayNG `securitys` 使用 `chacha20-poly1305/aes-128-gcm/auto/none/zero`，新建默认第 0 项 |
| 2026-06-19 | 协议点检 | ✅ URL-style TLS allowInsecure 导出完成；VLESS/Trojan 等 TLS 分享导出同时写 `insecure` 与 `allowInsecure`，true/false 均按 v2rayNG `1/0` 输出 |
| 2026-06-19 | 协议点检 | ✅ TLS 证书 pin 与 allowInsecure 运行语义完成；配置 `pinnedPeerCertSha256` 时生成运行配置会按 v2rayNG 将 `allowInsecure` 置为 false |
| 2026-06-19 | 协议点检 | ✅ TLS/Reality SNI fallback 完成；运行配置生成时空 `serverName` 会按 v2rayNG 从传输 host/authority 或服务器域名补齐 |
| 2026-06-19 | 协议点检 | ✅ URL-style userInfo 编码完成；Trojan/WireGuard/Hysteria2/HTTP 分享导出对密码、私钥和用户密码做 URI 编码，特殊字符 round-trip 保留 |
| 2026-06-19 | 协议点检 | ✅ URL-style 空备注默认值完成；分享链接缺少 fragment 时按 v2rayNG 将导入节点名设为 `none`，订阅导入同样保留 |
| 2026-06-19 | 协议点检 | ✅ 分享链接支持列表文案完成；解析器支持列表、失败提示、本地化与导入/扫码说明统一覆盖 `https://`、`socks4://`、`socks5://`、`hy2://` |
| 2026-06-19 | 协议点检 | ✅ finalMask `fm` 完成；分享链接导入导出保留 `streamSettings.finalmask`，NodeEdit 可填写 FinalMask raw JSON |
| 2026-06-19 | 协议点检 | ✅ TCP HTTP 头伪装完成；NodeEdit 可选择 v2rayNG `none/http`，保存 `tcpSettings.header.request`，分享链接 `headerType=http` round-trip 保留 |
| 2026-06-19 | 协议点检 | ✅ TCP 默认 query 导出完成；无 `streamSettings` 的 VLESS/Trojan 分享导出按 v2rayNG 普通 TCP 节点补齐 `security/type/headerType`，Trojan 补 `insecure=0`/`allowInsecure=0` |
| 2026-06-19 | 协议点检 | ✅ HTTPUpgrade/XHTTP 传输参数完成；`type=httpupgrade` host/path 导出保留，NodeEdit 可选择 httpupgrade，XHTTP `mode/extra` 可手动填写并 round-trip 保留 |
| 2026-06-19 | 协议点检 | ✅ XHTTP mode 枚举完成；导入、导出、NodeEdit 保存和运行配置均按 v2rayNG `auto/packet-up/stream-up/stream-one` 归一化，非法值兜底 `auto` |
| 2026-06-20 | 协议点检 | ✅ Browser Dialer profile 模式完成；WS/XHTTP 手动节点支持 `Disable/OkHttp/WebView` 选择与回填，运行配置输出剥离 profile 元数据 |
| 2026-06-20 | 协议点检 | ✅ H2 传输 Host 列表完成；手动 `h2` 节点保存时 Host 按 v2rayNG 逗号拆分为 `httpSettings.host` 数组，空 Path 回退 `/` |
| 2026-06-20 | 阶段 4 | ✅ DNS 服务器过滤完成；remote/domestic DNS 按 v2rayNG 仅保留纯 IP、`https/tcp/quic` CoreDNS 与 `localhost`，VPN DNS 仅保留纯 IP，过滤空时回退默认 |
| 2026-06-19 | 阶段 4 | ✅ 开机自启安装兼容修正；移除受限 `ohos.permission.RECEIVER_STARTUP_COMPLETED` manifest 声明，保留 Harmony `AUTO_STARTUP` 启动原因下的自动连接处理，普通调试签名安装不再被授权 ACL 拦截 |
| 2026-06-19 | 阶段 3 | ✅ 节点去重 profile 语义完成；普通节点按 v2rayNG `ProfileItem.equals` 近似语义忽略备注、分享链接 fragment 与 runtime tag 差异，full/proxy-chain/policy-group 复杂节点不参与重复删除 |
| 2026-06-19 | 协议点检 | ✅ gRPC 传输模式完成；NodeEdit 可选择 v2rayNG `gun/multi`，分享链接 `mode=multi` 与 `grpcSettings.multiMode` round-trip 保留 |
| 2026-06-19 | 协议点检 | ✅ KCP 传输参数完成；`type=kcp` 的 `headerType`/`seed`/`mtu`/`tti` 导入导出保留，并生成 v2rayNG 风格 `kcpSettings` + `finalmask.udp` |
| 2026-06-19 | 协议点检 | ✅ SOCKS 分享认证导出完成；用户密码导出为 v2rayNG 去 padding `base64(user:pass)` userInfo，无认证导出 `Og`，导入导出保留认证信息 |
| 2026-06-19 | 协议点检 | ✅ Shadowsocks/SOCKS base64 padding 完成；分享导出按 v2rayNG 去掉 userInfo base64 末尾 `=`，Shadowsocks base64 userInfo 同步 URI 编码 |
| 2026-06-19 | 协议点检 | ✅ SOCKS scheme 别名完成；`socks4://` / `socks5://` 分享和订阅导入归一为 `socks` outbound，导出继续使用 `socks://` |
| 2026-06-19 | 协议点检 | ✅ Shadowsocks legacy 尾斜杠兼容完成；整段 base64 旧格式允许 `host:port/`，同时保留 method 小写化与密码冒号解析 |
| 2026-06-19 | 协议点检 | ✅ Shadowsocks plugin 导出对齐完成；SIP002 `obfs=http` plugin 可导入为 TCP HTTP 伪装，导出按 v2rayNG 不回写 `plugin` 查询参数 |
| 2026-06-19 | 协议点检 | ✅ Shadowsocks 手动 method 选项完成；NodeEdit 按 v2rayNG `ss_securitys` 补齐 `chacha20`/`xchacha20`/`none`/`plain` 与 2022-blake3 全列表 |
| 2026-06-19 | 阶段 5 | ✅ 资源 URL 二维码导入完成；Assets 页新增 v2rayNG `add_qrcode` 等价入口，扫码 URL 后预填自定义资源添加表单 |
| 2026-06-19 | 阶段 5 | ✅ 自定义资源名称唯一性校验完成；新增/编辑/扫码预填/本地导入均按 v2rayNG asset remarks 语义拒绝重复名称 |
| 2026-06-19 | 阶段 5 | ✅ 本地文件资源编辑入口对齐完成；本地导入资源保留覆盖导入/删除，不再进入编辑表单，对齐 v2rayNG `url == "file"` 行为 |
| 2026-06-19 | 阶段 5 | ✅ 内置 Geo 文件更新对齐 v2rayNG；Assets 页新增 `geoip-only-cn-private.dat` 状态/单独更新/删除/本地覆盖，一键更新固定拉取 Loyalsoldier/geoip raw 文件 |
| 2026-06-19 | 阶段 5 | ✅ Geo 下载源选择对齐 v2rayNG；Assets 页补齐 `runetfreedom/russia-v2ray-rules-dat` 与 `Chocolate4U/Iran-v2ray-rules`，并改为动态源菜单 |
| 2026-06-20 | 阶段 5 | ✅ Geo/自定义资源下载代理兜底完成；本地 HTTP 代理暴露时先经 `127.0.0.1:10809` 下载，失败后自动直连，未暴露代理时保持直连 |
| 2026-06-19 | 阶段 4 | ✅ 运行配置变更自动重启对齐 v2rayNG；Settings/Route/PerApp 保存、导入/扫码/新增/选择当前节点后标记待重启，首页恢复时运行中自动 stop/start 应用新配置 |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 端口跳跃间隔完成；`mportHopInt` 可导入导出并在 NodeEdit 手动填写，导出时按 v2rayNG 规则规范化 |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 TLS/insecure 导出完成；分享链接导出按 v2rayNG 显式写入 `security=tls` 与 `insecure=1/0` |
| 2026-06-20 | 协议点检 | ✅ Hysteria2 security query 保留完成；分享链接导入时记录 `security`，缺省回退 `tls`，导出时按 v2rayNG 写回原值 |
| 2026-06-20 | 协议点检 | ✅ Hysteria2 security 手动/运行对齐完成；NodeEdit 可选择/回填 `none/tls`，运行配置按 security 保留 TLS 或省略 `tlsSettings` |
| 2026-06-20 | 阶段 3 | ✅ 订阅刷新选中节点保留完成；更新/更新全部按 v2rayNG 通过备注、server、port、password 多级匹配旧选中节点，匹配失败回退新导入首节点 |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 证书 pin 完成；`pinSHA256` 可从分享链接导入导出，并可在 NodeEdit 手动填写写入 outbound |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 bandwidth/obfs/port-hop 运行配置完成；启动配置生成 `finalmask.quicParams` brutal 带宽、`udpHop` 和 `salamander` mask |
| 2026-06-19 | 协议点检 | ✅ Hysteria2 runtime core 形状完成；启动配置按 v2rayNG 归一为 Xray `protocol=hysteria`、`hysteriaSettings.auth`、TLS/pin 与 finalmask |
| 2026-06-19 | 协议点检 | ✅ 普通手动节点编辑回填完成；节点详情可重新打开手动协议节点，NodeEdit 回填字段并原位更新 VLESS/VMess/Trojan/Shadowsocks/SOCKS/HTTP/WireGuard/Hysteria2 |
| 2026-06-19 | 协议点检 | ✅ WireGuard reserved 默认值完成；分享链接、`.conf` 导入和手动 builder 缺省写入 `[0,0,0]`，导出保留 `reserved=0,0,0` |
| 2026-06-19 | 协议点检 | ✅ WireGuard MTU 默认值完成；分享链接和 `.conf` 导入缺省 `mtu` 时按 v2rayNG 写入 `1420`，导出保留 `mtu=1420` |
| 2026-06-19 | 协议点检 | ✅ TLS/Reality ALPN 选项完成；NodeEdit 按 v2rayNG `streamsecurity_alpn` 限定 ALPN，Hysteria2 手动与运行配置缺省/非法 ALPN 兜底 `h3` |
| 2026-06-19 | 协议点检 | ✅ Mux 协议适用范围完成；全局 Mux 跳过 v2rayNG 禁用协议与 XHTTP，VLESS flow 节点使用 `concurrency=-1` |
| 2026-06-19 | 协议点检 | ✅ Mux XUDP UDP/443 策略枚举完成；Settings/存储/运行配置按 v2rayNG `mux_xudp_quic_value` 限定 `reject/allow/skip`，旧非法值兜底 `reject` |
| 2026-06-19 | 协议点检 | ✅ Fragment finalmask 运行配置完成；TLS/Reality 生成 `finalmask.tcp/udp`，Reality 默认 `packets=1-3`，已有 finalmask 和代理链 dialerProxy 会跳过 |
| 2026-06-19 | 协议点检 | ✅ Fragment packets 枚举完成；Settings 按 v2rayNG `fragment_packets` 限定 `tlshello/1-2/1-3/1-5`，保存与运行配置均兜底非法值 |
| 2026-06-19 | 协议点检 | ✅ Core loglevel 枚举完成；Settings/存储/运行配置按 v2rayNG `core_loglevel` 限定 `debug/info/warning/error/none`，旧非法值兜底 `warning` |
| 2026-06-19 | 协议点检 | ✅ 本地 SOCKS 默认端口完成；`pref_socks_port` 默认对齐 v2rayNG 为 10808，Harmony HTTP inbound 兼容端口避让到 10809 |
| 2026-06-19 | 自查 | ✅ Hypium 回归断言清理完成；动态策略组订阅过滤改为大小写不敏感，手动 WireGuard `reserved` 空输入恢复 v2rayNG `[0,0,0]` 缺省，测试改用 routing/outbound 语义断言 |
| 2026-06-19 | 阶段 4 | ✅ 扫码 native 分享兜底完成；Scanner 在单链接解析失败后复用 `CGoConvertShareLinksToXrayJson` 转换结果，批量保存 outbounds 并标记运行配置待重启 |
| 2026-06-19 | 阶段 4 | ✅ 剪贴板导入提示 i18n 完成；订阅编辑/详情/面板、扫码页与 JSON 导入页的粘贴成功、读取失败、空剪贴板和无有效文本提示均跟随当前语言 |
| 2026-06-20 | 阶段 4 | ✅ 扫码相册图片导入完成；Scanner 新增 v2rayNG `select_photo` 等价入口，Photo Picker 选择图片后用 ScanKit `detectBarcode.decode` 解码二维码并复用节点/订阅/native 批量导入链路 |
| 2026-06-19 | 阶段 4 | ✅ 外部分享文本导入完成；注册 Harmony `sendData/text/plain` 入口，对齐 v2rayNG `ACTION_SEND`，分享来的订阅 URL、单节点链接与 native 批量/base64/Clash 文本可导入并标记运行配置待重启 |
