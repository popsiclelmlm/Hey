# Hey VPN 路线图（对标 v2rayNG）

本文件记录 Hey 在 HarmonyOS Next 上对标 Android v2rayNG 的完成度评估与分阶段实施规划。
评估基于真实代码（截至 2026-06-18），而非声称状态。配套页面/功能对照见
[`v2rayng-feature-map.md`](v2rayng-feature-map.md)。

## 一、真实完成度评分

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| 应用骨架 / 导航 / i18n | ✅ 95% | 双语、分层清晰、路由完整 |
| 原生 TUN 数据通路 | ✅ 90% | 代码就位且**真机闭环验证通过（2026-06-15）**——TUN→Xray→出站→可上网 |
| 分享链接解析 | ✅ 88% | vless/vmess/trojan/ss/socks/http/wireguard/hy2 已覆盖，WireGuard `.conf` 整段导入已支持；**缺 TUIC** |
| 订阅管理 | 🟡 91% | 多分组 + 旧版迁移 + 编辑/重排/批量更新全部 + 订阅级不安全 URL 开关 + 当前分组删除全部 + 自动更新设置/前台到期刷新 + 本地 HTTP 代理经由更新；**缺后台调度** |
| Xray 配置生成 | 🟡 72% | 普通节点生成 TUN/metrics/DNS/routing/HTTP 代理配置；完整自定义 Xray config 可校验后原样运行；高级出站目标仍待补 |
| 节点延迟测速 / 排序 | ✅ 80% | `CGoPing` 真测速 + 排序，需真机验证 |
| 路由设置页 | ✅ 80% | 广告拦截、自定义规则、预设规则集导入/导出均已生效；高级出站目标与真机规则回归待补 |
| Geo 资产管理 | ✅ 85% | 下载 / 自定义 URL / 备份还原已实现 |
| 分应用代理 | 🔴 20% | 仅开关持久化，**无真实应用列表枚举** |
| 设置页 | 🟡 70% | 核心项持久化并生效 |
| 扫码导入 | 🔴 30% | **仅粘贴，无相机扫码** |
| 导出 / 分享 | ✅ 82% | 文本/文件导出、节点二维码与系统分享面板已完成；后续主要是真机分享目标兼容回归 |
| 平台集成 | 🔴 0% | 无快捷方式 / 卡片 / 深链导入 |

### Native 桥接现状

`libxray.so` 导出 13 个 CGo 函数，当前 `napi_init.cpp` 仅接通 4 个：

- 已接通：`CGoRunXrayFromJSON`、`CGoStopXray`、`CGoPing`、`CGoSetTunFd`
- **闲置**：`CGoQueryStats`（真实流量统计）、`CGoReadGeoFiles` / `CGoCountGeoData`（geo 校验）、
  `CGoTestXray`（配置预检）、`CGoXrayVersion`、`CGoConvertShareLinksToXrayJson`、
  `CGOConvertXrayJsonToShareLinks`、`CGoGetFreePorts`、`CGoRunXray`

> 当前 `getStats()` 返回的是 C++ 侧近似计数，非内核真实统计。

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
- `CGoReadGeoFiles` / `CGoCountGeoData` → geo 文件校验与计数

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

- 相机扫码（`@kit.ScanKit` scanBarcode）替代纯粘贴
- 二维码生成（节点分享）
- TUIC 协议解析 + 运行
- 完整自定义 Xray config 导入与原样运行（已完成）
- 自动订阅更新后台调度（前台到期刷新已完成）
- 运行中经由本地代理更新订阅（已完成）

### 阶段 5：平台集成（鸿蒙特性）

- Want / 深链导入（对应 v2rayNG UrlScheme）
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
