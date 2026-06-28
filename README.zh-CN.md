<div align="center">

<img src="design/app-icon/startIcon.png" alt="Hey VPN" width="160" height="160" />

# Hey VPN

**为 HarmonyOS NEXT 打造的原生 Xray / sing-box 代理客户端。**

<p>
  <img src="https://img.shields.io/badge/platform-HarmonyOS%20NEXT-0A0A0A" alt="platform" />
  <img src="https://img.shields.io/badge/target-6.0.1%20(21)-1E88E5" alt="target SDK 6.0.1(21)" />
  <img src="https://img.shields.io/badge/core-Xray%20%2B%20sing--box-6E56CF" alt="Xray and sing-box cores" />
  <img src="https://img.shields.io/badge/version-1.3.2-E85D04" alt="version 1.3.2" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-3DA639" alt="license GPL-3.0" /></a>
</p>

[English](README.md) · 简体中文

</div>

---

Hey VPN 是一个用 ArkTS 写的 HarmonyOS NEXT 应用。当前代码接入了 Stage 模型、
VPN Extension Ability、服务卡片、WorkScheduler、ScanKit 扫码、桌面快捷方式、
`hey://` 深链、系统分享导入，以及一层负责加载原生代理内核的 N-API 桥。

项目的主运行路径是 Xray。sing-box 也已经随包打入，并且可以在设置里切换，但它在应用里的
能力范围目前比 Xray 窄，属于预览路径。

## 当前状态

Xray 路径是这个仓库里的主路径。它支持 VPN 模式和仅代理模式，可以从当前节点/配置生成运行时
Xray 配置，启动和停止 HarmonyOS VPN Extension，并通过随包的 `libheytun2socks.so` 转发
VPN 流量。

当前两个内核共用的 VPN 数据面是：

```text
HarmonyOS VPN TUN fd
  -> libheytun2socks.so
  -> 127.0.0.1:10810（本地 SOCKS/mixed 入站）
  -> Xray 或 sing-box outbound
```

也就是说，应用现在不会把 TUN fd 直接交给 Xray 或 sing-box。为什么要这样做、OpenHarmony Go
fork 和 TLSDESC 构建路线怎么来的，见
[`docs/harmonyos-go-tls-wall.md`](docs/harmonyos-go-tls-wall.md)；原生库构建说明见
[`docs/building-native-cores.md`](docs/building-native-cores.md)。

sing-box 路径目前支持 VPN 模式下的单个转换后 outbound。转换器覆盖 VLESS、VMess、Trojan、
Shadowsocks、AnyTLS 和 TUIC，并处理基础的 tcp/ws/grpc/http/httpupgrade 传输以及
none/tls/reality 安全层。它还不支持完整配置、代理链、策略组、仅代理模式、Hysteria2、
WireGuard、SOCKS、HTTP，或 sing-box 自身的细粒度流量统计。

## 代码里已经实现的能力

- HarmonyOS 入口：`EntryAbility`、`HeyVpnAbility`、`ControlCardAbility`、
  `SubscriptionUpdateWorkAbility`、桌面快捷方式、`hey://` 路由和 `text/plain` 系统分享导入。
- 页面：服务器列表、节点详情/编辑、导入、JSON 导入、高级出站、订阅、订阅详情/编辑、路由、
  设置、语言、分应用代理、资源、日志、扫码、备份、导出和关于。
- 节点与订阅：多订阅分组、当前分组和节点状态、自定义 User-Agent、过滤、前置/后置配置字段、
  手动刷新、到期刷新、WorkScheduler 后台刷新、搜索/排序/清理，以及通过原生桥做真实延迟测试。
- 导入：订阅 URL、v2rayN 明文/BASE64 文本、Xray outbound/full JSON、Clash 风格 YAML 节点、
  WireGuard 配置文件、二维码、系统分享文本，以及 `vless://`、`vmess://`、`trojan://`、
  `ss://`、`socks://`、`socks4://`、`socks5://`、`http://`、`https://`、`wireguard://`、
  `hysteria2://`、`hy2://`、`anytls://`、`tuic://` 分享链接。
- 导出：`formatOutboundJsonToShareLink` 已实现协议的节点分享链接、节点详情/导出页二维码、
  路由规则 JSON，以及本地完整备份 JSON。
- Xray 运行时配置：给 `tun2socks` 用的 VPN SOCKS 入站、可选本地 SOCKS/HTTP 代理、
  proxy/direct/block 出站、DNS、嗅探、mux、fragment/finalmask、Hysteria2 运行时形态、
  WireGuard IPv6 处理、代理链、策略组、metrics 和路由规则。
- 路由：流量模式、域名策略、LAN/CN/全局/伊朗/俄罗斯/广告拦截预设、自定义规则、锁定规则、
  process/port/network/protocol 匹配，以及规则导入导出。
- 分应用代理：支持代理/绕过模式和持久化包名列表。HarmonyOS NEXT 这里没有通用全局应用枚举，
  所以手动或预设包名仍是当前设计的一部分。
- 资源与诊断：内置 Geo 来源、自定义 Geo 资源 URL、原生 Geo 计数、运行日志、Core 日志、
  可选速度显示、持久累计流量、更新检查、远端 IP 信息，以及中英文和更多语言资源。
- 备份恢复：本地 JSON 覆盖 profile、订阅分组、设置、路由规则、分应用列表和自定义资源 URL。
  运行流量累计和服务卡片状态属于设备本地状态，代码里刻意不迁移。

## 已知限制

- VPN 闭环仍需要更多 HarmonyOS NEXT 真机和系统版本验证。部分模拟器或系统镜像没有 VPN 授权组件。
- sing-box 是预览运行路径：它已经随包、可选择、可启动，但应用层只在 VPN 模式下用它跑一个已支持的
  outbound。

## 项目结构

```text
AppScope/                         应用元数据、版本、图标和名称
entry/src/main/ets/               ArkTS UI、存储、服务、路由和 VPN 代码
entry/src/main/cpp/               N-API 桥和原生库打包
entry/src/main/cpp/prebuilt/      随包的 arm64-v8a .so 文件
libsingbox/                       sing-box c-shared 库的 Go wrapper
scripts/                          应用构建/安装/日志脚本和原生库构建脚本
docs/                             原生构建与 HarmonyOS 相关说明
```

## 构建与安装

`build-profile.json5` 是 DevEco Studio 的本地配置文件，方便个人调试，因此不会提交到仓库。
首次打开新拉取的工程前，请先把 `build-profile.example.json5` 复制为 `build-profile.json5`，然后在
DevEco Studio 里配置本机的调试或发布签名。证书路径、密钥密码等签名内容只保留在本地。

当前构建配置里的 target SDK 是 `6.0.1(21)`，compatible SDK 是 `5.1.1(19)`。
项目里的烟测脚本封装了 `hvigorw` 和 `hdc`。

构建签名 HAP：

```bash
./scripts/device_vpn_smoke_test.sh build
```

如果 DevEco Studio 不在 macOS 默认路径，可以显式传入 SDK 和 hvigor 路径：

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
HVIGOR=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
./scripts/device_vpn_smoke_test.sh build
```

构建产物默认位于：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

常用真机命令：

```bash
./scripts/device_vpn_smoke_test.sh targets
./scripts/device_vpn_smoke_test.sh doctor
./scripts/device_vpn_smoke_test.sh install
./scripts/device_vpn_smoke_test.sh logs
```

## 原生库

`libheyvpn.so` 由 `entry/src/main/cpp/napi_init.cpp` 构建。CMake 会把随包的 Go 共享库拷进
HAP 原生库目录：

| 库 | 当前作用 | 构建状态 |
| --- | --- | --- |
| `libxray.so` | 主 Xray 运行时，导出启动、停止、测速和统计入口。 | `scripts/build_libxray_ohos.sh` 已脚本化。 |
| `libsingbox.so` | 可选 sing-box 运行时，导出启动、停止、版本和探针入口。 | `scripts/build_libsingbox_ohos.sh` 已脚本化。 |
| `libheytun2socks.so` | 把 HarmonyOS VPN TUN fd 转发到内核本地入站。 | 已随包并使用，由 `scripts/build_tun2socks_ohos.sh` 构建。 |

两个已脚本化的 Go 构建都走 OpenHarmony Go fork + `GOOS=openharmony`。Go fork 工具链建议放在
仓库外面；`hvigor clean` 会删除仓库内的 `build/` 目录。

## 许可协议

版权所有 (C) 2026 popsiclelmlm

Hey VPN 基于 [GNU 通用公共许可证 v3.0（GPL-3.0）](LICENSE) 开源。你可以自由使用、修改和再分发
（包括商用），但衍生作品须同样以 GPL-3.0 开源，并向接收者提供对应源码。

项目打包了 Xray-core（MPL-2.0），基于 libXray（MIT）构建，同时打包 sing-box
（GPL-3.0-or-later），并使用基于 xjasonlyu/tun2socks（MIT）的 tun2socks 适配层。
这些组件保留各自的协议，详见 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。
