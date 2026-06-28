# IPv6 泄漏防护

> 状态：**已修复并真机验证**（ALN-AL80 / HarmonyOS）
> 最后更新：2026-06-28
> 关键结论：曾误判为"鸿蒙平台不接管 IPv6"，真因是 **VPN 路由 `gateway`/`isDefaultRoute` 写法不对被系统丢弃**。改成「空 gateway + `isDefaultRoute:false`」后 `::/0` 正常装进 TUN，泄漏消失。

## 1. 问题现象

连上 VPN 后，浏览器访问 https://ip.sb 看到的出口是 **IPv6**，且该 IPv6 的**归属地是本地运营商 + 本地城市**——即用户真实的 IPv6 地址，**没有经过代理**。

- IPv4 出口正常（节点落地 IP），说明 VPN 整体在工作。
- 唯独 IPv6 绕过隧道，从物理网卡直出 → **真实地址泄漏**。

### 判断泄漏的正确方法

IPv6 地址是一长串十六进制，落地 IP 和本地 IP 肉眼难辨，**不要比地址字符串**，只看**归属（运营商 / 国家 / ASN）**：

- 归属 = 本地运营商 + 所在城市 → ❌ 泄漏
- 归属 = 节点落地机房 / 代理国家 → ✅ 走代理

辅助手段（绕开 ip.sb 双栈优先 IPv6 的干扰）：分开测两个协议的出口
- IPv4 出口：https://api-ipv4.ip.sb/ip
- IPv6 出口：https://api-ipv6.ip.sb/ip

> 注意：ip.sb 是双栈站点，浏览器按 Happy Eyeballs 优先用 IPv6 连它，所以首页显示的是 IPv6。这只解释"为什么看到 IPv6"，不改变"看到的是本地地址 = 泄漏"的结论。

## 2. 架构背景

Hey 的数据面：

```
Harmony TUN(vpnExtension) → libheytun2socks(xjasonlyu/tun2socks + gvisor, 双栈)
  → 本地 SOCKS(127.0.0.1) → Xray / sing-box 核心 → 节点服务器
```

关键点：

- **真实 DNS 解析**（不是 fake-ip）：应用拿到的是目标的真实 IP。
- TUN 由 `entry/src/main/ets/vpn/VpnConstants.ets` 的 `createDefaultVpnConfig` 生成。
- 配置生成走 `XrayConfig.ets` 的 `buildRuntimeXrayConfig`；节点类型分 `outbound` / `proxy-chain` / `policy-group`（走 `buildDnsConfig`/`buildRoutingRules`）与 `full`（**原样透传**，不走这两个函数，需单独注入）。

## 3. 泄漏机制

IPv6 泄漏的本质：**系统的 IPv6 流量没进隧道，从物理网卡直出**。

物理网卡（如 wlan0）有运营商下发的全局 IPv6（如 `2409:8a00:...`）和一条 `::/0` v6 默认路由。只要 TUN 没把 `::/0` v6 抢过来，双栈站点的 IPv6 流量就走物理口出网。IPv4 因为 TUN 始终用 `0.0.0.0/0` 接管成功，所以从不泄漏。

**Hey 是真实解析、没有 fake-ip 这道防线**（见 §5.2），所以防泄漏只能押在"TUN 接管 IPv6"这一个点上——一旦 `::/0` 没装进 TUN，就漏。而这正是本次的卡点（见 §6）。

## 4. 鸿蒙 vpnExtension 的 IPv6 接管（理论）

官方 API 支持 IPv6 接管，"三件套"：

1. `isIPv6Accepted: true`（**官方默认 false**，这就是"不开开关默认泄漏"的根因之一）
2. `addresses` 里加一个 IPv6 `LinkAddress`，`family: 2`（IPv4=1, IPv6=2）
3. `routes` 里加 `::/0`（destination `::`, prefixLength 0, family 2）

补充：

- **单条 `::/0` 即可，不需要拆 `::/1` + `8000::/1`**。Android 拆是因为 VpnService 只能加路由不能删系统默认路由，靠更长前缀抢占；鸿蒙是声明式整体下发，无此需要。
- 防回环：`::/0` 接管后，核心连节点的出站 socket 不能被自己的路由捞回。Hey 用 `blockedApplications=[自身包名]` 排除本应用流量（等效 protect），对 IPv6 同样生效。
- **VPN 路由只能通过 `createVpnConnection().create(config)` 的 `VpnConfig.routes` 一次性下发**，没有 `addRoute`/`setRoute`/`updateConfig` 补充接口。

## 5. 研究过程

### 5.1 决定性参考：arror/x4h

[arror/x4h](https://github.com/arror/x4h)（Xray 鸿蒙客户端）的 `entry/src/main/ets/manager/vpn/VpnConfigManager.ets` 是 IPv6 能在鸿蒙上接管的**实证**，也是本次找到真因的钥匙。它的 v6 路由写法与我们原来的**关键差异**见 §6。

### 5.2 与 Clash / Mihomo 的架构对比（为什么它们关 IPv6 也不漏）

Clash Verge 默认关闭 IPv6 却基本不泄漏，根因是 **fake-ip**：

- 应用查域名 → 内核返回假 IPv4（198.18.x.x）→ 应用连假 IP → 内核反查域名 → 真实解析发生在**代理服务器侧**。
- 客户端本机**从不产生指向真实 IPv6 目标的流量**，所以即使不接管 IPv6 也不泄漏。

Hey 是真实解析、无 fake-ip，故必须真正接管 IPv6 路由。
来源：https://wiki.metacubex.one/en/config/dns/

### 5.3 走过的弯路：误判为"平台不接管 v6" ⚠️

排查中一度得出错误结论"HarmonyOS 不把 v6 路由生效到隧道、平台限制无解"。误判来自两个陷阱：

- **`/proc/net/ipv6_route`、`/proc/net/route` 只显示主路由表**；而 VPN 路由进的是**独立策略路由表**。当时看到 vpn-tun 主表里没有 `::/0`，又发现 v4 的 `0.0.0.0/0` **同样**不在主表却能走代理，错误推断成"v4 策略生效、v6 不生效=平台限制"。
- 实际上换遍 v6 地址（ULA→全局）、前缀（`/126`→`/64`）、`::/0`/`2000::/3`、bypass 开关都无效，**真正的变量一直没动到**——路由对象本身的 `gateway`/`isDefaultRoute` 字段写法。

教训：判断 v6 有没有真进 TUN，**最终以 `ip.sb` 归属为准**；`/proc` 主表只能做参考，且要知道 VPN 路由在策略表里。

## 6. 根因与修复 ✅

**根因：`VpnConfig.routes` 里 v6 `RouteInfo` 的 `gateway` / `isDefaultRoute` 写法不对，HarmonyOS 会静默丢弃该 v6 路由**（只保留地址自带的连接路由，不装 `::/0` 默认路由 → 全局 v6 走物理口）。同样的写法 v4 能生效、v6 不行。

`entry/src/main/ets/vpn/VpnConstants.ets` 的 `createVpnRoute`：

| 字段 | ❌ 原来（v6 被丢弃） | ✅ 修复后（参考 x4h） |
|---|---|---|
| `gateway` | `{ address: '::', family: 2, port: 0 }` | `{ address: '' }`（空字符串，不带 family/port） |
| `isDefaultRoute` | `prefixLength === 0`（`::/0` 时为 `true`） | `false`（即使是 `::/0` 也填 `false`） |

改成右列写法后，`/proc/net/ipv6_route` 里 vpn-tun **出现 `::/0`**，全局 v6 进隧道，泄漏消失。**v4 路由保持原写法不动**（本来就生效）。

```ts
// createVpnRoute：v6 专用写法
if (family === ADDRESS_FAMILY_IPV6) {
  return {
    interface: VPN_INTERFACE_NAME,
    destination: { address: { address, family }, prefixLength },
    gateway: { address: '' },     // 空 gateway 是关键
    hasGateway: false,
    isDefaultRoute: false          // ::/0 也填 false
  };
}
```

## 7. 完整修复清单（已落地）

分两层，对应两个提交。

### 7.1 TUN 层：真正把 v6 抓进隧道（`VpnConstants.ets` + `Profile.ets`）

- **`createVpnRoute`**：v6 路由改用「空 gateway + `isDefaultRoute:false`」（§6，**核心修复**）。
- **`createDefaultVpnConfig`**：`routeIpv6 = true` 恒接管 v6（不论开关），并 `isIPv6Accepted: true`。即使节点没 v6，v6 进隧道后由核心处理（见 §8），不再外漏。
- **`Profile.ets` 地址表**：TUN 的 v6 客户端地址从 ULA `fc00::` 改为全局段 `2001:db8::`/64（更标准；ULA 在 RFC 6724 源地址选择上对全局目标处于劣势）。

### 7.2 核心层：v6 抑制（`XrayConfig.ets`）

让进了隧道的 v6 在核心被正确处置，对"走系统 DNS 的 app"额外加一道防线：

- **DNS `queryStrategy`**：`buildDnsConfig` 设 `ipv6Enabled ? 'UseIP' : 'UseIPv4'`。关 v6 时核心只返回 A 记录，走系统 DNS 的 app 拿不到 AAAA、不发起 v6。
- **路由 blackhole**：`buildRoutingRules` 在关 v6 时，于 direct/CN 规则**之前**插入 `{ type:'field', outboundTag:'block', ip:['::/0'] }`，把所有 v6 目标秒拒，逼应用回落 IPv4。
- **full 透传配置注入**：`full` 类型配置不走上面两个函数，新增 `suppressIpv6InFullConfig`，对 full 配置注入同等的 `queryStrategy=UseIPv4` + `block ::/0`（确保 blackhole 出站存在）。
- sing-box 侧已有 `dns.strategy = ipv6Enabled ? 'prefer_ipv4' : 'ipv4_only'`，路由"非私网全部→proxy"无 CN-direct 分支，配合 TUN 接管即可不漏。

## 8. 开关语义（修复后）

`ipv6Enabled`（设置项「启用 IPv6」）现在控制**核心怎么处置已被 TUN 抓进来的 v6**，两种状态都不泄漏：

| 开关 | v6 流量 | ip.sb 结果 | 适用 |
|---|---|---|---|
| **关**（默认） | 进隧道 → 核心 `block ::/0` 秒拒 → 应用回落 v4 | 只显节点 v4，无 v6 | 节点**没有** v6（绝大多数）；回落最快最干净 |
| **开** | 进隧道 → 核心转发给节点 | 节点支持 v6→显**节点 v6**；节点没 v6→失败回落 v4 | 节点**支持** v6 时才开 |

默认 `ipv6Enabled: false`（`SettingsStore.ets`），即推荐状态。

## 9. 验证方法

1. **必须 clean 重编**（DevEco CLI 增量构建会用缓存不重编改动）：
   `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk hvigorw --no-daemon clean assembleHap`
2. 安装后**强杀再冷启动**：`hdc shell aa force-stop com.lmlm.hey`（reinstall 不一定重启生成配置的主进程）。
3. 连接 VPN 后，查 v6 路由是否真进 TUN（决定性）：
   `hdc shell "cat /proc/net/ipv6_route | grep vpn-tun"` → 应出现一行 `00000000…00000000 00 …`（即 `::/0`，第 2 列前缀=`00`）。
4. ip.sb 看 IPv6 **归属**（不是地址字符串）：落地机房=不泄漏；本地运营商=仍泄漏。
5. 分协议确认：`api-ipv4.ip.sb/ip`（应为节点）vs `api-ipv6.ip.sb/ip`。

## 10. 排查教训（踩过的坑）

- **`/proc` 只显主表**：VPN 路由在独立策略表，主表看不到 `0.0.0.0/0`/`::/0` 也属正常；判断 v6 是否接管以 ip.sb 归属为准（§5.3）。
- **reinstall 不重启主进程**：VPN 扩展进程每次连接重拉（新代码），但生成配置的**主进程**可能残留旧 JS，必须 `aa force-stop` 后冷启动才验证得到新代码。
- **`configBytes` 是压缩值**：诊断日志里的 `configBytes` 是 `injectXrayLogFile` 用无缩进 `JSON.stringify` 压缩后的长度，不能拿它判断配置是否变化（曾被误导很久）。
- **增量构建用缓存**：改完 `.ets` 不 clean，hvigor 可能直接打包旧编译产物。验证字节码是否含改动：解 HAP 的 `ets/modules.abc` grep 字符串字面量。
- **配置类型分流**：`type=full` 是原样透传，核心侧防护需单独注入（§7.2）。

## 参考链接

- 鸿蒙 vpnExtension API：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-net-vpnextension
- 鸿蒙 net.connection（NetAddress/RouteInfo，family 值）：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-net-connection
- **arror/x4h（v6 路由写法实证，本次真因来源）**：https://github.com/arror/x4h
- Mihomo DNS（fake-ip / 空 AAAA）：https://wiki.metacubex.one/en/config/dns/
- HarmonyOS "vpn-tun ipv6 不生效" 论坛帖（实为路由写法问题）：https://developer.huawei.com/consumer/cn/forum/topic/0201202921009691906
