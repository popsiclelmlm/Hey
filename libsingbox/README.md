# libsingbox —— sing-box 内核的 HarmonyOS 封装（Phase 0 spike）

> **现状（已超越本文档）**：sing-box 已作为可选第二内核接入主干，且与 Xray **统一走
> tun2socks 数据面**——内核起一个本地 SOCKS(mixed) 入站（`127.0.0.1:10810`），由
> `libheytun2socks.so` 把 Harmony TUN fd 的流量转发进来。**不再用本文 Stage B 描述的
> `CGoSetTunFd` + tun 入站 + OpenTun + gvisor tun 栈**那条路线（那是 Phase 0 的设想，
> 最终因 Go-on-musl TLS 墙与 TUN 栈复杂度被弃用）。本文保留为 Phase 0 历史记录；
> 当前数据面架构见仓库根 `README` 与 [`docs/harmonyos-go-tls-wall.md`](../docs/harmonyos-go-tls-wall.md)，
> sing-box 配置生成见 [`entry/src/main/ets/core/SingboxConfig.ets`](../entry/src/main/ets/core/SingboxConfig.ets)。

这是「给 App 加 sing-box 作为可选内核」的第一步：**只验证 sing-box 能不能在
HarmonyOS（musl libc）上编译运行**，还没碰 UI、没做完整配置生成器、没做内核选择。

目标很窄——确认 sing-box（同样是 Go）不会撞死在那堵 Go-on-musl TLS 墙上
（见 [`scripts/build_libxray_ohos.sh`](../scripts/build_libxray_ohos.sh) 顶部注释）。

## 文件

| 文件 | 作用 |
|---|---|
| `main.go` | C 导出 + CallResponse(base64) 协议（对齐 libXray）+ 分阶段 spike 入口 |
| `platform_stub.go` | `libbox.PlatformInterface` 实现（**版本最敏感**，OpenTun 返回宿主 tun fd） |
| `go.mod` | 钉死 sing-box tag |
| `../scripts/build_libsingbox_ohos.sh` | 交叉编译成 `libsingbox.so`，照搬 libxray 工具链 |

## 分两阶段验证（务必按顺序）

### Stage A —— 编译 + dlopen + 一次 cgo 调用（最致命的问题）

只用 `CGoSingBoxVersion()`。它一次性回答：c-shared 能不能编出来、dlopen 会不会
被 musl 以 IE-TLS 拒、一次 `cgo->Go` 调用会不会 SIGSEGV。

1. 装好 DevEco SDK（脚本默认 `/Applications/DevEco-Studio.app/.../sdk`，或设
   `DEVECO_SDK_HOME` / `OHOS_NATIVE_HOME`）。
2. 编译：
   ```bash
   bash scripts/build_libsingbox_ohos.sh
   ```
   - 第一次会 `go mod tidy` 拉 sing-box 依赖（需联网）。
   - **大概率要先过编译期接口断言**：`platform_stub.go` 里
     `var _ libbox.PlatformInterface = ...` 会报缺/多哪个方法。按编译器提示，
     对着 `go doc github.com/sagernet/sing-box/experimental/libbox.PlatformInterface`
     增删方法即可。`libbox.Setup` 的签名同理（main.go 里有标注）。
3. 临时挂到现有 native bridge 验证（不进主干）：
   - [`entry/src/main/cpp/CMakeLists.txt`](../entry/src/main/cpp/CMakeLists.txt:19)
     的 `foreach(PREBUILT_LIB libxray.so)` 加上 `libsingbox.so`，让它被拷进产物。
   - 在 [`napi_init.cpp`](../entry/src/main/cpp/napi_init.cpp) 里临时 `dlopen("libsingbox.so")`
     + `dlsym("CGoSingBoxVersion")`，加一个 NAPI 导出。
   - **从 VPN 线程**（不是 UI 线程）调它，确认返回版本号且不崩。
     —— Stage A 通过，说明 sing-box 在 OHOS 上「能活」。

### Stage B —— 喂 tun fd 跑一条真连接

1. 在 [`HeyVpnAbility.startVpn()`](../entry/src/main/ets/vpn/HeyVpnAbility.ets:63) 里临时叉一条：
   拿到 `tunFd` 后，不走 Xray，改成
   `CGoSetTunFd(tunFd)` → `CGoStartSingBox(base64({basePath, config}))`。
2. `config` 用一条写死的最小 sing-box JSON：一个 `tun` inbound + 一个你手头能用的
   outbound + 直连 route。spike 期刻意关掉易触雷的功能：
   - `route.auto_detect_interface: false`
   - DNS 固定上游（如 `1.1.1.1`），别走平台 resolver 回调
   - tun `stack: gvisor`（走被 patch 覆盖的 readv/writev 路径，别用 system stack）
3. 真机连上后用浏览器/curl 验证能过流量。通了，Phase 0 收工。

## 已知雷区（spike 就是来踩这些的）

- **`libbox.PlatformInterface` 方法集随版本变** —— 编译断言会逼你对齐，见上。
- **gvisor Fstat patch 是否命中** —— sing-box 经 sing-tun 走 sagernet 的 gvisor
  fork，tun 栈可能自实现，未必命中 libxray 那处 `isSocketFD`。构建脚本里 patch
  不中只告警；设备上若 tun 因 Fstat 报错，去 sing-tun 的 gvisor 栈找等价处理。
- **netlink / 接口监控** —— `platform_stub.go` 默认关掉平台接口监控
  （`UsePlatformDefaultInterfaceMonitor=false`），让问题先暴露。若 sing-box 自带的
  netlink 监控在 OHOS-musl 上崩，改成返回 `true` 并在
  `StartDefaultInterfaceMonitor` 里给 listener 喂一个固定默认接口。
- **TLS 墙复发** —— 理论上和 libxray 同路（`GOOS=android`），但 sing-box cgo 依赖
  更多，不排除新的 musl 符号缺失；Stage A 就是来证伪这一点的。

## 通过之后（Phase 1+，本次不做）

把 native bridge 和 config 生成抽象成 `ProxyCore` 接口（start/stop/stats/buildConfig），
Xray 先重构进去；再写 sing-box 配置生成器；最后加「全局内核开关」设置项。
