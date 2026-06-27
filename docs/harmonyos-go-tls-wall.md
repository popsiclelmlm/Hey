# HarmonyOS Go cgo TLS 墙：VPN 启动崩溃排查记录

> 状态：根因已确认，Xray / sing-box / tun2socks 的现役产物都已改走
> `GOOS=openharmony` + TLSDESC。本文记录问题怎么定位、为什么最后回到
> tun2socks 数据面，以及后续构建时要避开的坑。
>
> 首次排查设备：ALN-AL80 / HarmonyOS 6.1.0.117(SP6C00E115R4P9) / API 23。
> 构建配方请以 [`building-native-cores.md`](building-native-cores.md) 为准。

---

## 1. 当时看到的现象

真机点「连接」后，主进程最后报：

```text
connection start failed: 启动 VPN 失败：启动 VPN 未确认完成：VPN 扩展没有回写启动完成状态。
```

这条错误本身不是根因。它的意思是：`ConnectionController.start()` 调了
`startVpnExtensionAbility()`，然后轮询共享的 `DiagnosticLog`，等 VPN 扩展进程写入
`Native VPN bridge started.` 或 `VPN start failed.`。12 秒内两个都没等到，于是主进程
只能认为启动失败。

如果 ArkTS 里正常抛异常，`catch` 会写入 `VPN start failed.`。所以「零回写」高度指向
VPN 扩展进程在写任何回执前就已经退出了，最常见的就是 native 层 SIGSEGV。

当时还有一个误导点：用户记得 1.1 版本（2026-06-05 发布）能跑。后面验证发现，把
1.1 的 `libxray.so` 字节级还原回来也会崩，说明这不是单纯的 App 二进制回归。

---

## 2. 崩溃栈给出的线索

清空 hilog 后在真机复现，抓到的关键栈大致是：

```text
Reason: Signal:SIGSEGV(SEGV_MAPERR)@0x000103ffd50323b7
Process name: com.lmlm.hey:vpn   life time: 2s
#00 pc 0x...fc3e38 libxray.so
#01 pc 0x...fc3dfc libxray.so
#02 pc 0x...0106e4 libheyvpn.so
#03 libace_napi.z.so ArkNativeFunctionCallBack
#06 at setNativeTunFd (HeyNative.ets:111)
#07 at startVpn (HeyVpnAbility.ets:101)
ArkEtsVm: runtime: SIGSEGV in managed thread (native code)
DfxUnwinder: Failed to step first frame, lr fallback
```

几个点很关键：

- 崩在进入 `libxray.so` 的第一个 cgo 调用附近。最开始是 preflight 的 `CGoTestXray`，
  去掉 preflight 后，下一次 `CGoSetTunFd` 又崩。
- `libheyvpn.so` 已经正确调到了 Go 导出的 C 符号，问题不是 N-API 没接上。
- 地址像野指针，栈也回不稳，很符合 Go runtime 在线程本地状态上读到垃圾值后的表现。

这让方向从「某个 Xray 函数写坏内存」转成了「Go runtime 在 HarmonyOS 线程上拿错了
TLS 里的 g 指针」。

---

## 3. 真正的问题：Android target 的 TLS 假设不适合 HarmonyOS

修复前的 `libxray.so` / `libsingbox.so` 都是用标准 Go 的
`GOOS=android GOARCH=arm64`，配 OHOS clang 编出来的。

这个组合能产出可加载的 `.so`，但里面有一个隐藏前提：Android target 会按 bionic 的
规则，把 Go 的 goroutine 指针 `g` 放在固定 TLS 槽里。`llvm-readelf -l libxray.so |
grep TLS` 为空，也就是没有真正的 ELF `PT_TLS` 段。

HarmonyOS 这里跑的是 musl，不是 bionic。在 ArkTS / native 外来线程上，那个固定槽并不
归 Go runtime 管：

- 槽里刚好是 0 时，Go 会走 `needm`，给这个外来线程补上 Go 的运行时状态，于是看起来能跑。
- 槽里是非零垃圾时，Go 会把它当成现成的 `g` 直接用，随后就是 SIGSEGV。

这也解释了「以前能跑，现在崩」这种很不舒服的现象。更保守地说，它说明运行环境变了：
可能是系统 OTA，也可能是 VPN 扩展进程的线程布局、TLS 初值或加载顺序变化。我们没有
证明是哪一个变化，但 1.1 旧二进制在同一台设备上也崩，足够排除「只是新代码写坏了」。

之前我们已经在 UI 线程冷调 cgo 时踩过同一类墙；这次更麻烦，因为 VPN 扩展线程也踩到了，
主链路不再只是「诊断按钮会崩」，而是连 VPN 都起不来。

---

## 4. 走过的路

| 尝试 | 结果 |
| --- | --- |
| 删掉 `HeyVpnAbility` 里的 `testNativeXrayConfig` preflight | 绕过了第一处冷 cgo，但下一个 `CGoSetTunFd` 继续崩，说明不是 preflight 自身的问题。 |
| 换回 1.1 的 `libxray.so` | 仍然崩，且故障地址一致。问题在运行环境和 target 假设上，不在这次新编出来的某个函数里。 |
| 把 `dlopen` 改成启动时链接 / DT_NEEDED | 没解决。native 模块本身仍是运行时加载，musl 对 TLS 模型的限制绕不过去。 |
| 换 sing-box 核 | 当时的 sing-box 也是 `GOOS=android`，同样没有 `PT_TLS`，会撞同一堵墙。 |
| 用 OpenHarmony Go fork 编 `GOOS=openharmony` | 方向成立：产物有真正的 `PT_TLS` 和 `R_AARCH64_TLSDESC`，外来线程 cgo 不再读 bionic 固定槽。 |

---

## 5. 能解 TLS 的方案：OpenHarmony Go fork + TLSDESC

OpenHarmony-SIG 维护了 Go 的 OpenHarmony 移植：

```text
https://gitcode.com/openharmony-sig/ohos_golang_go
branch: release-branch.go1.24
version: go1.24.5
```

这个 fork 给 arm64 补了 TLSDESC，也就是 musl 能在 `dlopen` 的共享库里处理的动态 TLS
模型。最小 cgo `c-shared` 冒烟验证看到了两个标志：

```text
PT_TLS 段：存在
tls_g 重定位：R_AARCH64_TLSDESC
```

这正好补上了标准 Go 两条路各自的短板：

- 标准 `GOOS=android`：能 `dlopen`，但外来线程上的 bionic TLS 槽不可靠。
- 标准 `GOOS=linux`：用真 ELF TLS，但会带 initial-exec TLS，musl 不接受这种库再被
  `dlopen`。
- `GOOS=openharmony` fork：用 TLSDESC，既能被 musl `dlopen`，也能让外来线程上的 cgo
  正常进入 Go runtime。

---

## 6. 为什么没有继续走 native-TUN

TLS 问题解决后，还剩一个版本鸿沟。

OpenHarmony Go fork 目前只到 go1.24.5；远端分支也只有 `release-branch.go1.24` 和更旧的
`master`（go1.22）。但当前 libXray 主线已经要求 go1.26.3，xray-core 从 2025-09 之后也
抬到了 go1.25 以上。上游 Go 到 1.26 仍没有 `GOOS=openharmony`。

而我们当时的 native-TUN 路径正好依赖较新的东西：

- `CGoSetTunFd` 是 libXray 在 2026-04-01 加的。
- 这条路依赖 xray-core 的 `proxy/tun` 包和 `platform.TunFdKey`。
- `xray-core v1.250803.0` 是 go1.24，可编，但没有 `proxy/tun` / `TunFdKey`。
- `xray-core v1.260206.0` 有 `proxy/tun/tun_android.go` / `TunFdKey`，但 go.mod 是
  `go 1.25.7`。

所以现成的 go1.24.5 fork 编不出带 native-TUN 能力的 Xray 核。要保留 native-TUN，就要
把 OpenHarmony Go 补丁前移到 go1.25 或 go1.26。这个方向并非不可做，但风险主要在
`cmd/dist`、`cmd/link`、runtime 和 syscall，尤其是 arm64 TLSDESC，短期内不适合作为
主线修复。

---

## 7. 最后选的路：回到 tun2socks 数据面

为了先把真机 VPN 救回来，最后选择恢复旧数据面：

```text
HarmonyOS TUN fd
  -> libheytun2socks.so
  -> 127.0.0.1:10810 SOCKS 入站
  -> Xray / sing-box outbound
```

这个方案的好处很直接：

- `tun2socks_adapter/go.mod` 是 `go 1.23.4`，不依赖 xray-core，用 go1.24.5 fork 能编。
- Xray 只需要提供 SOCKS 入站，钉在 libXray `20d70a98` / xray-core `v1.250803.0` 就够了。
- 不需要 `CGoSetTunFd`、`proxy/tun` 或 `TunFdKey`。
- Go-on-HarmonyOS 的 TLS 问题仍然用 fork + TLSDESC 正面解决，不再碰 bionic 固定槽。

代价也要承认：数据面多了一层 gVisor 用户态转发，性能和维护成本都不如 native-TUN 干净。
但它构建确定、风险可控，而且和项目早期跑通过的设计一致。

---

## 8. 当前实现状态

截至 2026-06-28，现役状态是：

- `libxray.so`：`GOOS=openharmony`，带 `PT_TLS + R_AARCH64_TLSDESC`，只导出
  `CGoRunXrayFromJSON` / `CGoStopXray` / `CGoPing` / `CGoQueryStats`。脚本见
  `scripts/build_libxray_ohos.sh`。
- `libsingbox.so`：同样用 OpenHarmony Go fork 重编，作为可选第二内核。它仍导出
  `CGoSetTunFd` 等历史生命周期符号，但 VPN 数据面已经不再把 TUN fd 交给 sing-box。
- `libheytun2socks.so`：负责读取 HarmonyOS TUN fd，并把流量转进本地 SOCKS 入站。
  现有产物已是 OpenHarmony fork + TLSDESC；构建脚本还待恢复，手工配方见
  [`building-native-cores.md`](building-native-cores.md)。
- `HeyVpnAbility.ets`：Xray 和 sing-box 都统一走 tun2socks 数据面，核心先起本地
  SOCKS 入站，再启动 `startNativeTun2Socks(tunFd, 127.0.0.1, 10810, mtu)`。
- `XrayConfig.ets` / `SingboxConfig.ets`：VPN 入站都改成本地 SOCKS / mixed 入站，
  不再生成核心自己的 TUN 入站。

当时真机验证结果：ALN-AL80 / HarmonyOS 6.1 上，原来的「VPN 扩展没有回写启动完成状态」
已消失，VPN 能连上，也能走通流量。

---

## 9. gVisor Fstat 补丁

tun2socks 和历史 native-TUN 栈都绕不开 gVisor 的 fd endpoint。这里有另一个 HarmonyOS
差异：VPN fd 可以 `readv` / `writev`，但会拒绝 `Fstat`。gVisor 的 `fdbased` endpoint
默认会用 `unix.Fstat` 判断这个 fd 是不是 socket；在 HarmonyOS VPN fd 上，这一步会失败。

所以 tun2socks 这边必须 patch：

```go
func isSocketFD(fd int) (bool, error) {
    return false, nil
}
```

对当前 SOCKS 版 `libxray.so` 来说，这个补丁通常不会命中，因为 Xray 已经不直接读 TUN fd。
脚本里仍保留了尽力而为的 patch，是为了防止历史依赖路径或后续实验重新踩到。

---

## 10. 构建和校验

完整构建步骤放在 [`building-native-cores.md`](building-native-cores.md)。这里只留几条最容易
忘的规则：

- OpenHarmony Go fork 放仓库外，默认路径是 `~/hey-ohos-build/ohos_golang_go`。不要放
  `<repo>/build/`，`hvigor clean` 会删。
- 公共环境：

```bash
CGO_ENABLED=1 \
GOOS=openharmony \
GOARCH=arm64 \
CC=<DevEco>/sdk/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang \
CXX=<DevEco>/sdk/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang++ \
CGO_CFLAGS="-ftls-model=global-dynamic" \
GOTOOLCHAIN=local
```

- `GOOS=openharmony` 下不要加 `-tags netgo`。OpenHarmony 的 net 端口需要 cgo，加了会报
  `_C_getifaddrs undefined`。
- 每次重编 `.so` 后至少看这几项：

```bash
strings -a entry/src/main/cpp/prebuilt/arm64-v8a/libxray.so | grep -m1 'GOOS=openharmony'
llvm-readelf -l entry/src/main/cpp/prebuilt/arm64-v8a/libxray.so | grep -i TLS
llvm-readelf -r entry/src/main/cpp/prebuilt/arm64-v8a/libxray.so | grep -i TLSDESC
nm -D entry/src/main/cpp/prebuilt/arm64-v8a/libxray.so | grep ' T .*CGo'
```

`libxray.so` 的 CGo 导出应该只有 4 个。`libxray.h` 是 cgo 生成的历史头文件，可能列出
现役 `.so` 不再导出的符号，判断导出集以 `nm -D` 为准。

---

## 11. 还没收尾的事

- 继续观察冷启动首连、DNS-over-UDP、长时间运行后的稳定性。
- 如果以后想回到 native-TUN，需要先做 go1.25+ 的 OpenHarmony 工具链前向移植；在那之前，
  不建议把 Xray 主线和 native-TUN 重新接回 VPN 数据面。
