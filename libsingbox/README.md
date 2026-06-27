# libsingbox：sing-box 的 HarmonyOS 封装

`libsingbox/` 是 Hey 内置 sing-box 核心的 Go wrapper。它把
`github.com/sagernet/sing-box/experimental/libbox` 编成
`entry/src/main/cpp/prebuilt/arm64-v8a/libsingbox.so`，再由
`libheyvpn.so` 通过 `dlopen` 加载。

这条路径已经不是早期的 Phase 0 spike 了：sing-box 现在能作为可选第二内核从设置里选择，
并参与 VPN 启停链路。不过它仍然是预览路径，能力边界比 Xray 窄。

## 当前状态

- 构建方式：使用 OpenHarmony Go fork，`GOOS=openharmony GOARCH=arm64`，产物带
  `PT_TLS + R_AARCH64_TLSDESC`。这和 Xray、tun2socks 是同一套 TLS 修复路线。
- sing-box 版本：`github.com/sagernet/sing-box v1.11.0`，锁在 `go.mod`。
- App 接入状态：已接入 native bridge、CMake 预置库拷贝、全局内核选择、VPN Extension
  启停链路。
- 数据面：和 Xray 统一走 `TUN fd -> libheytun2socks.so -> 127.0.0.1:10810 -> core SOCKS inbound`。
  当前 VPN 启动路径不会把 TUN fd 直接交给 sing-box。
- 运行限制：目前只支持 VPN 模式 + 单节点 outbound。代理链、策略组、完整 JSON 配置、
  proxy-only 模式、复杂路由规则和更完整的统计能力还没有和 Xray 对齐。

## 数据面

当前 sing-box 配置生成器会创建一个本地 `mixed` 入站：

```text
HarmonyOS VPN TUN fd
  -> libheytun2socks.so
  -> 127.0.0.1:10810 mixed inbound
  -> sing-box outbound
```

也就是说，sing-box 只负责从本地 SOCKS/mixed 入站接流量，再按转换后的节点配置出站。
`tun` inbound、`OpenTun()` 和 sing-box 自己的 gVisor TUN 栈不是当前 App 数据面的一部分。

wrapper 里仍然保留 `CGoSetTunFd` 和 `platform_stub.go` 的 `OpenTun()` 实现。这是早期
native-TUN spike 留下的接口，也方便以后重新做实验；但当前 [HeyVpnAbility.ets](../entry/src/main/ets/vpn/HeyVpnAbility.ets)
不会调用 `setNativeSingboxTunFd()`。

## 配置生成

运行时配置由 [SingboxConfig.ets](../entry/src/main/ets/core/SingboxConfig.ets) 生成。它把
项目里的 Xray outbound JSON 转成 sing-box JSON。

目前覆盖的协议和形态：

- VLESS
- VMess
- Trojan
- Shadowsocks
- AnyTLS
- TUIC
- 传输层：tcp / ws / grpc / http upgrade
- 安全层：none / tls / reality，含基础 uTLS 指纹

目前没有覆盖或没有完整对齐的能力：

- Hysteria2 / WireGuard / SOCKS / HTTP 节点转 sing-box 出站
- Xray 的完整配置导入
- 策略组、代理链、负载均衡、规则集、广告拦截等高级路由
- proxy-only 模式下的本地代理复用
- sing-box 自身的细粒度统计；现阶段主要依赖 tun2socks 侧流量计数兜底

`validate_test.go` 用真实 `libbox.NewService` 校验配置 schema。它目前覆盖了
VLESS Reality、VMess WS+TLS、Trojan gRPC+TLS、Shadowsocks 四类代表性配置；AnyTLS 和
TUIC 已在生成器里实现，但还应补对应测试样例。

## 原生导出

`libsingbox.so` 当前导出 4 个 C 符号：

| 符号 | 当前用途 |
| --- | --- |
| `CGoStartSingBox` | VPN 线程调用，启动 sing-box service。 |
| `CGoStopSingBox` | VPN cleanup 调用，停止 service。 |
| `CGoSingBoxVersion` | 真实 cgo 版本入口。UI 不应冷调用；About 页使用 `CoreInfo.ets` 里的编译期常量。 |
| `CGoSetTunFd` | 历史 native-TUN 实验入口；当前 VPN 数据面不调用。 |

入参和返回值沿用 libXray 风格：入参是 base64(JSON)，返回 base64(CallResponse JSON)，这样
`entry/src/main/cpp/napi_init.cpp` 可以复用同一套解码逻辑。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `main.go` | c-shared 导出、base64 CallResponse 协议、libbox service 启停。文件头注释仍带有早期 spike 语境，实际状态以本 README 为准。 |
| `platform_stub.go` | `libbox.PlatformInterface` 的最小实现。当前 SOCKS 数据面基本不依赖 `OpenTun()`，但 `libbox.NewService` 仍需要这个接口对象。 |
| `validate_test.go` | 用真实 sing-box v1.11.0 校验生成配置能否被 `libbox.NewService` 接受。 |
| `go.mod` / `go.sum` | 锁定 sing-box 及其依赖。 |
| `../scripts/build_libsingbox_ohos.sh` | 使用 OpenHarmony Go fork 交叉编译 `libsingbox.so`。 |

## 构建

准备 OpenHarmony Go fork 和 DevEco Native 工具链后：

```bash
bash scripts/build_libsingbox_ohos.sh
```

脚本固定走 `GOOS=openharmony`（已无 `GOOS_TARGET` 开关），默认配置：

```text
GO_TAGS="with_gvisor with_utls with_clash_api"
OHOS_GO_FORK=~/hey-ohos-build/ohos_golang_go
```

这几个 tag 都有实际作用：

- `with_gvisor`：保留 sing-box 需要的 gVisor 相关能力。
- `with_utls`：Reality / uTLS 配置需要。
- `with_clash_api`：`libbox.NewService` 路径需要。

不要加 `netgo`。OpenHarmony 的 net 端口需要 cgo，禁掉 cgo resolver 会遇到
`_C_getifaddrs undefined` 一类错误。

构建后建议至少检查：

```bash
SO=entry/src/main/cpp/prebuilt/arm64-v8a/libsingbox.so

strings -a "$SO" | grep -m1 'GOOS=openharmony'
strings -a "$SO" | grep -m1 'github.com/sagernet/sing-box@v1.11.0'
llvm-readelf -l "$SO" | grep -i TLS
llvm-readelf -r "$SO" | grep -i TLSDESC
nm -D "$SO" | grep ' T .*CGo'
```

期望看到 `PT_TLS`、`R_AARCH64_TLSDESC`，以及
`CGoStartSingBox` / `CGoStopSingBox` / `CGoSetTunFd` / `CGoSingBoxVersion`。

## 本地校验

配置 schema 校验可以在 macOS 本机跑：

```bash
cd libsingbox
go test -tags "with_gvisor with_utls with_clash_api" -run TestGeneratedConfigs -v
```

这个测试只验证 `libbox.NewService` 接受配置，不会启动 service，也不需要真实 TUN fd。

真机验证仍以完整 VPN 链路为准：选择 sing-box 内核，启动一个 sing-box 支持的单节点，
日志里应看到 `sing-box started`、`tun2socks started` 和 `Native VPN bridge started.`。

## 已知风险和后续

- `platform_stub.go` 仍是最小实现。sing-box / libbox 升级时，`PlatformInterface` 方法集可能变化，
  需要按编译错误补齐。
- 构建脚本里保留了 sagernet gvisor 的 `isSocketFD` patch 尝试，但当前 SOCKS 数据面通常不走
  sing-box 的 TUN fd endpoint。真正读 TUN fd 的是 `libheytun2socks.so`。
- `nativeSingboxVersion()` 这种真实 cgo 入口不要从 UI 冷调用。About 页显示版本请继续用
  `BUNDLED_SINGBOX_VERSION`。
- 下一步主要是补齐预览路径能力：更多协议测试样例、proxy-only 模式、规则/策略能力、统计能力，
  以及把 sing-box 启停错误和配置转换错误做得更细。
