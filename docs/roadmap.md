# Hey VPN 路线图（对标 v2rayNG）

本文件记录 Hey 在 HarmonyOS Next 上对标 Android v2rayNG 的完成度评估与分阶段实施规划。
评估基于真实代码（截至 2026-06-18），而非声称状态。配套页面/功能对照见
[`v2rayng-feature-map.md`](v2rayng-feature-map.md)。

## 一、真实完成度评分

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| 应用骨架 / 导航 / i18n | ✅ 95% | 双语、分层清晰、路由完整 |
| 原生 TUN 数据通路 | ✅ 93% | 代码就位且**真机闭环验证通过（2026-06-15）**——TUN→Xray→出站→可上网；IPv6 地址/路由与 outbound Happy Eyeballs 已按设置生成，待真机回归 |
| 分享链接解析 | ✅ 90% | vless/vmess/trojan/ss/socks/http/wireguard/hy2 已覆盖，WireGuard `.conf` 整段导入已支持；导入失败后可走 native 转换兜底支持 v2rayN 多行/base64 与 Clash.Meta YAML（待重建 `.so` 真机验证）；**缺 TUIC** |
| 订阅管理 | 🟡 91% | 多分组 + 旧版迁移 + 编辑/重排/批量更新全部 + 订阅级不安全 URL 开关 + 当前分组删除全部 + 自动更新设置/前台到期刷新 + 本地 HTTP 代理经由更新；**缺后台调度** |
| Xray 配置生成 | 🟡 79% | 普通节点生成 TUN/metrics/DNS/routing/HTTP 代理和本地 SOCKS 配置，HTTP/SOCKS 代理支持局域网共享监听，SOCKS 支持启动前动态端口；完整自定义 Xray config 可校验后原样运行；代理链和策略组 JSON 可生成多跳/负载均衡 outbounds，且已有普通节点可构建为代理链/策略组配置；高级出站目标 UI 仍待补 |
| 节点延迟测速 / 排序 | ✅ 82% | `CGoPing` 真测速 + 排序，测速 SOCKS inbound 优先使用 `CGoGetFreePorts` 动态端口；需真机验证 |
| 路由设置页 | ✅ 80% | 广告拦截、自定义规则、预设规则集导入/导出均已生效；高级出站目标与真机规则回归待补 |
| Geo 资产管理 | ✅ 90% | 下载 / 自定义 URL / 备份还原已实现；Geo 文件 native 计数/校验已接线，待重建 `.so` 真机验证 |
| 分应用代理 | 🟡 70% | 开关、黑白名单、手动包名、应用枚举和 VPN 应用映射已接线；仍受平台可见性限制，待真机回归 |
| 设置页 | 🟡 76% | 核心项持久化并生效，本地 SOCKS 代理静态/动态端口、UDP、认证已写入运行配置 |
| 扫码导入 | ✅ 80% | 粘贴导入和 ScanKit 相机扫码已接线，待真机相机权限/机型回归 |
| 导出 / 分享 | ✅ 82% | 文本/文件导出、节点二维码与系统分享面板已完成；后续主要是真机分享目标兼容回归 |
| 平台集成 | 🔴 20% | Want / URL Scheme 深链导入已完成；快捷方式 / 卡片仍待补 |

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
- TUIC 协议解析 + 运行
- 完整自定义 Xray config 导入与原样运行（已完成）
- 自动订阅更新后台调度（前台到期刷新已完成）
- 运行中经由本地代理更新订阅（已完成）

### 阶段 5：平台集成（鸿蒙特性）

- ✅ Want / 深链导入（对应 v2rayNG UrlScheme）
- 桌面快捷方式、服务卡片（widget）
- 开机自启（受平台权限限制，量力而行）

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
| 2026-06-18 | 阶段 4 | ✅ 订阅自动更新设置与前台到期刷新完成；后台任务调度仍待补 |
| 2026-06-18 | 阶段 4 | ✅ 运行中经由本地 HTTP 代理更新订阅完成；`appendHttpProxy` 生成 `http-in` 并让订阅拉取优先走代理、失败回退直连 |
| 2026-06-18 | 阶段 4 | ✅ 完整自定义 Xray config 导入与原样运行完成；手动节点/profile 记录 `configType`，导出/清无效兼容 full config |
| 2026-06-18 | 阶段 4 | ✅ 自定义配置文件选择导入完成；JSON 导入页支持 `.json`/`.txt`/`.conf` 文件读取后校验保存 |
| 2026-06-18 | 阶段 4 | ✅ 节点配置文件导出完成；Export 页支持当前分组复制文本与保存 `.txt` 文件 |
| 2026-06-18 | 阶段 4 | ✅ WireGuard `.conf` 整段导入完成；`[Interface]`/`[Peer]` 文本会归一化为 Xray wireguard outbound |
| 2026-06-18 | 阶段 4 | ✅ 系统分享面板完成；Export 批量文本和节点详情单节点链接走 Harmony `sendData` 分享，失败回退剪贴板 |
| 2026-06-18 | 阶段 0 | ✅ TUN IPv6 设置接线完成；`preferIpv6` 持久化后生成 IPv6 TUN 地址与 `::/0` 默认路由 |
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
| 2026-06-18 | 阶段 5 | 🟡 代理链运行核心完成；JSON 导入支持 `proxy-chain`，运行时生成多跳 outbounds 并通过 `sockopt.dialerProxy` 串联，专门编辑器/成员选择待补 |
| 2026-06-18 | 阶段 5 | 🟡 策略组/负载均衡运行核心完成；JSON 导入支持 `policy-group`，运行时生成 `routing.balancers`、leastPing/leastLoad 观测配置与默认 balancer 路由，专门编辑器/订阅筛选待补 |
| 2026-06-18 | 阶段 5 | 🟡 高级出站构建器完成；可从已有普通 outbound 节点生成 `proxy-chain`/`policy-group` JSON，并拒绝完整配置、嵌套高级节点和无效节点，专门 UI 仍待补 |
