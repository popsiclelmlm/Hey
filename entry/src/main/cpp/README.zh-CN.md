# Hey VPN 原生内核

[English](README.md) · 简体中文

`libheyvpn.so` 是 ArkTS 的 N-API 桥。它在运行时 `dlopen` 同目录下打包的几个 Go
共享库：

- `libxray.so` —— Xray 代理内核（基于 XTLS/libXray 编译）。导出：
  - `CGoRunXrayFromJSON(const char* base64Request) -> char*` —— 用一份 JSON 配置
    启动 Xray（VPN 配置会在 `127.0.0.1:10810` 开一个本地 SOCKS 入站）。
  - `CGoStopXray() -> char*`
  - `CGoQueryStats(const char* base64Request) -> char*` —— 读取 Xray 指标（expvar）。
  - `CGoPing(const char* base64Request) -> char*` —— 单节点出站延迟测速；桥这边用一份
    base64 JSON 请求 `{datDir, configPath, timeout, url, proxy}` 调它，再从 base64 的
    `{success, data, err}` 响应里解析出毫秒延迟。
- `libsingbox.so` —— 可选的第二内核（sing-box）。导出 `CGoStartSingBox` /
  `CGoStopSingBox`（外加一个 UI 线程安全的探针）。和 Xray 一样，它的 VPN 配置开的也是
  本地 SOCKS 入站，而不是原生 TUN 入站。
- `libheytun2socks.so` —— `tun2socks` 适配器。导出 `HeyTun2SocksStart(fd, host, port, mtu)` /
  `HeyTun2SocksStop()` 以及字节计数器。它把鸿蒙 VPN TUN fd 上的流量转发进内核的本地
  SOCKS 入站。

## 数据面

```text
TUN fd  ->  libheytun2socks.so  ->  127.0.0.1:10810（内核 SOCKS 入站）  ->  出站
```

内核自带的原生 TUN 入站（`CGoSetTunFd` / `protocol: "tun"`）**不**走 VPN 数据面。
Go 在鸿蒙（musl）上的 TLS 墙，加上原生 TUN 入口的工具链缺口，把数据面退回到了
`TUN fd -> tun2socks -> SOCKS 入站` 这条路。详见
[`docs/harmonyos-go-tls-wall.md`](../../../../docs/harmonyos-go-tls-wall.md)。

## 构建

随包发布的 `libxray.so` / `libsingbox.so` / `libheytun2socks.so` 都用
**OpenHarmony Go fork**（`GOOS=openharmony`，arm64 **TLSDESC**）编译，这样 cgo 才能从
ArkTS／外来线程里正常工作，几个库也能在 musl 上干净地 `dlopen`。原生 TUN 入口是早期实验
留下来的：`libxray.so` 干脆不导出 `CGoSetTunFd`，`libsingbox.so` 则还带着它（连同
`OpenTun()` 桩），只是 SOCKS 数据面从来不会去调它。

`scripts/build_libxray_ohos.sh` 和 `scripts/build_libsingbox_ohos.sh` 默认就走
`openharmony` fork 这条路。权威的构建步骤（工具链配置、固定的版本号、各库的导出符号、产物
校验）在 [`docs/building-native-cores.md`](../../../../docs/building-native-cores.md)；
底层 TLS 的来龙去脉在
[`docs/harmonyos-go-tls-wall.md`](../../../../docs/harmonyos-go-tls-wall.md)。
CMake 会在编完 `libheyvpn.so` 之后，把
`entry/src/main/cpp/prebuilt/arm64-v8a/` 下预编译好的 `.so` 拷进 HAP 的原生库目录。
