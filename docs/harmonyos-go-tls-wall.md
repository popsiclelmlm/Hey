# HarmonyOS Go cgo TLS 墙 —— VPN 启动崩溃排查与修复方案

> 状态：**根因已定，修复方向已验证可行，正在落地**（2026-06-21）
> 设备：ALN-AL80 / HarmonyOS 6.1.0.117(SP6C00E115R4P9) / API 23

本文记录"真机点连接 → 启动 VPN 失败：VPN 扩展没有回写启动完成状态"这一问题的
完整排查过程、根因、探索过的所有方案及其结论，以及选定的落地路径。配套背景见
`docs/vpn-native-runtime-fix.md`（当前 native-TUN 链路文档）。

---

## 1. 现象

真机点击"连接"后报：

```
connection start failed: 启动 VPN 失败：启动 VPN 未确认完成：VPN 扩展没有回写启动完成状态。
```

机制：主进程 `ConnectionController.start()` 调 `startVpnExtensionAbility()` 后，
轮询共享的 `DiagnosticLog` 文件，等 VPN 扩展进程回写 `Native VPN bridge started.`
或 `VPN start failed.`，12 秒内一个都没等到 → 报上面的错。

**"零回写"只可能是 VPN 扩展进程在写任何回执前就崩了**（任何 `throw` 都会被 catch
并回写 `VPN start failed.`）。用户记得 1.1 版本（2026-06-05 发布，仅两周前）是好的。

---

## 2. 根因：GOOS=android 的 bionic TLS 槽，被环境变化踩爆

### 2.1 真机崩溃栈（决定性证据）

清空 hilog → 真机复现 → 抓到：

```
Reason: Signal:SIGSEGV(SEGV_MAPERR)@0x000103ffd50323b7
Process name: com.lmlm.hey:vpn   life time: 2s
#00 pc 0x...fc3e38 libxray.so          ← 崩在 libxray 的 Go 运行时内部
#01 pc 0x...fc3dfc libxray.so
#02 pc 0x...0106e4 libheyvpn.so         ← napi 正确地调到了 g_setTunFd
#03 libace_napi.z.so ArkNativeFunctionCallBack
#06 at setNativeTunFd (HeyNative.ets:111)
#07 at startVpn (HeyVpnAbility.ets:101)
ArkEtsVm: runtime: SIGSEGV in managed thread (native code)
DfxUnwinder: Failed to step first frame, lr fallback   （反复出现）
```

- 崩点是**进入 libxray 的第一个 cgo 调用**（先是 preflight 的 `CGoTestXray`，
  去掉后变成 `CGoSetTunFd`）。
- 故障地址 `0x103ffd50323b7` 是个野指针；栈无法正常回溯——典型的 **Go 运行时
  TLS/栈被当成垃圾解引用**的特征。

### 2.2 为什么是 android target 的 TLS 问题

`libxray.so` / `libsingbox.so` 都由 `GOOS=android GOARCH=arm64` + OHOS clang 编译。

- **GOOS=android**：Go 把 goroutine 指针 `g` 存进 **Android bionic 的固定 TLS 槽**
  （`.so` **没有 PT_TLS 段**，验证：`llvm-readelf -l libxray.so | grep TLS` 为空）。
- HarmonyOS 是 **musl** libc，不是 bionic。在 ArkTS/native 外来线程上，那个 bionic
  槽里的值**不受 Go 控制**：
  - 槽里恰好是 0 → Go 走 `needm` 正常分配 `g` → 能跑（**1.1 当时就是这样**）。
  - 槽里是非零垃圾 → Go 当成已有 `g` 直接解引用 → **SIGSEGV**（现在这样）。

**所以"1.1 好的、现在崩"不是代码/二进制回归，而是环境变化**（几乎可以肯定是
设备 HarmonyOS 系统 OTA 升级，把 VPN 扩展线程的那个 TLS 槽从良性翻成了垃圾）。
验证：把 `libxray.so` 还原成 1.1 的字节级相同二进制，**照崩、地址一样**。

> 这堵墙在更早的会话里已记录（见全局记忆 `libxray-ohos-tls-dlopen-wall`），当时
> 的结论是"UI 线程 cgo 崩、但 VPN 扩展还能用"。本次的新发现是：**墙已经蔓延到
> VPN 扩展线程**，VPN 主路也崩了。

---

## 3. 探索过的方案及结论

| 方案 | 结论 |
|---|---|
| 删掉 `HeyVpnAbility` 里的 `testNativeXrayConfig` preflight（第 78 行的冷 cgo） | ✅ 修掉了那一处崩溃，但**下一个 cgo 调用 `setNativeTunFd` 接着崩**——证明不是某个函数的问题 |
| 还原 1.1 的 `libxray.so` | ❌ 照崩，地址一样 → **环境问题，非二进制回归** |
| `dlopen` 改启动时链接（DT_NEEDED） | ❌ 旧会话已验证：musl 只给"初始镜像库"静态 TLS，而整个 native 模块是被运行时 `dlopen` 的，链接救不了 |
| 改用 sing-box 核 | ❌ `libsingbox.so` 同样 `GOOS=android`、同样无 PT_TLS → 撞同一堵墙；换核救不了 |
| **OHOS 官方 Go fork（`GOOS=openharmony`）** | ✅ **正解**，见第 4 节 |

---

## 4. 验证可行的修复方向：OHOS Go fork + TLSDESC

OpenHarmony-SIG 维护了 Go 的官方移植：**`gitcode.com/openharmony-sig/ohos_golang_go`**
（分支 `release-branch.go1.24`，即 go1.24.5）。它为 arm64 补上了 **TLSDESC（通用动态
TLS）** 支持——这正是 musl 能在 `dlopen` 的库里解析的 TLS 模型。

### 已完成的验证

1. 用本机 go1.25.4 做 bootstrap，`make.bash` 编出 OHOS go1.24.5 工具链。
2. 最小 cgo c-shared 冒烟测试（`GOOS=openharmony`）：

```
PT_TLS 段：存在（真正的 ELF TLS，不再走 bionic 槽）
tls_g 重定位：R_AARCH64_TLSDESC   ← 通用动态模型，musl dlopen 可解析
```

这两点同时满足，意味着用该工具链编出的 `.so`：**既能被 libheyvpn 在 musl 上
`dlopen`，外来线程 cgo 调用也不会读到垃圾 TLS** —— 两难一次解掉。

---

## 5. 卡点：核版本与工具链版本的鸿沟

OHOS Go fork 只发布到 **go1.24.5**（master 是更旧的 go1.22，无 1.25/1.26 分支）。
而当前 native-TUN 链路依赖的东西要求更高的 Go：

- 当前 `libXray` 要求 **go 1.26.3**；其依赖 `xray-core` 自 2025-09 起就要求 **go ≥ 1.25**。
- 上游 Go **直到 1.26 都不含 openharmony 移植**（`grep -r openharmony go1.26.3/src` 为 0）。
- VPN 数据面用的 **`CGoSetTunFd`** 是 libXray 在 **2026-04-01** 才加的，且从加入起
  go.mod 就是 go1.26；它依赖 xray-core 的 `proxy/tun` 包 + `platform.TunFdKey`，
  而：
  - `xray-core v1.250803.0`（go1.24，2025-08）：**没有 `proxy/tun`、没有 `TunFdKey`**。
  - `xray-core v1.260206.0`（go1.25.7，2026-02）：**有** `proxy/tun/tun_android.go` + `TunFdKey`。

**结论**：用现成的 go1.24.5 fork **编不出有原生 TUN 能力的核**。native-TUN 链路
最低需要 go1.25 工具链（前向移植）。

---

## 6. 两条落地路径

两条路**都用 OHOS fork 的 TLSDESC 作为真正的 TLS 修复**，区别在数据面与工具链：

### 路径 A：tun2socks 复活（选定）

复活 `5a21b4e`（2026-06-03 "Remove tun2socks VPN adapter"）之前的旧数据面：

```
TUN fd → libheytun2socks.so（xjasonlyu/tun2socks v2.6.0 + gVisor netstack）
       → Xray 的 SOCKS 入站 → Xray outbound
```

- `tun2socks_adapter/go.mod` 是 **`go 1.23.4`、不依赖 xray-core** → 用 go1.24.5 fork 直接编。
- `libxray.so` 只需 **SOCKS 入站**（远古特性）→ go1.24 的 `xray-core v1.250803.0`
  即可，**不需要 `CGoSetTunFd`/`proxy/tun`/`TunFdKey`**。
- ✅ **无需任何上游 Go 移植**；构建侧完全确定。
- ⚠️ 代价：把数据面**改回** TUN→tun2socks→SOCKS（动 napi + XrayConfig + HeyVpnAbility），
  重建 2 个 Go 库；重新引入已删掉的 gVisor 用户态中转层（性能略低、多一库维护）。
- 核：xray-core 2025-08（go1.24）。

### 路径 B：go1.25 工具链前向移植（备选）

把 OHOS 的 openharmony 补丁从 go1.24.5 前移到上游 go1.25，编出 go1.25 OHOS 工具链，
保留当前 native-TUN 架构，用 `xray-core v1.260206.0`（go1.25.7）重建 libxray。

- ✅ 保留更干净的原生 TUN 架构，App 代码几乎不动。
- ⚠️ 需要移植 `cmd/dist` / `cmd/link`（arm64 TLSDESC 是硬骨头）/ runtime / syscall，
  跨一个大版本有冲突风险，构建侧不确定，可能多轮迭代。
- 核：xray-core 2026-02（go1.25.7）。

### 选定：路径 A（tun2socks 复活）

理由：**构建侧完全确定**（不赌上游 Go 移植能否成），是"已验证能跑的旧设计 +
正确的 TLSDESC 修复"的组合，风险最低。执行上**不做 `git revert 5a21b4e`**（会与
近 3 周的 sing-box / 设置重构大面积冲突），而是从该提交**挑出数据面三件套**
（tun2socks 适配器源码 + 构建脚本 + SOCKS 入站配置 + napi 适配器控制）重新接到
当前代码上。

---

## 7. 关键事实速查

- 当前 prebuilt `libxray.so`（d37ab36）= GOOS=android、含 12 个 CGo 导出、**会崩**。
- 1.1 的 `libxray.so` = 同为 GOOS=android、仅 4 个导出、**也会崩**（环境问题）。
- VPN 必需的 napi 符号：`CGoRunXrayFromJSON` / `CGoStopXray` / `CGoPing` /
  `CGoSetTunFd`（native-TUN 路）。tun2socks 路**不需要** `CGoSetTunFd`。
- OHOS Go fork：`gitcode.com/openharmony-sig/ohos_golang_go @ release-branch.go1.24`
  （go1.24.5），已在本机 `build/native/ohos_golang_go/`（gitignored）编好。
- 构建 OHOS 目标：`GOOS=openharmony GOARCH=arm64 CC=<OHOS clang> CGO_CFLAGS="-ftls-model=global-dynamic" GOTOOLCHAIN=local`。
- `gvisor` 的 `isSocketFD` Fstat 补丁对所有 target 都要打（Harmony VPN fd 拒绝 Fstat）。

---

## 8. 下一步（路径 A）

1. **试编 tun2socks 适配器**：从 `5a21b4e^` 取回 `tun2socks_adapter/` + `build_tun2socks_ohos.sh`，
   用 go1.24.5 fork（`GOOS=openharmony`）编 `libheytun2socks.so`，确认依赖树不卡 go1.25
   且产物带 PT_TLS + TLSDESC。**编过了再动 App 代码。**
2. 编 SOCKS-入站版 `libxray.so`（xray-core v1.250803.0 + go1.24.5 fork）。
3. 把数据面三件套接回当前代码（napi 适配器控制 + XrayConfig 改 SOCKS 入站 +
   HeyVpnAbility 改走适配器）。
4. `scripts/device_vpn_smoke_test.sh build`（含 `hvigor clean`）→ `install` → 真机验证；
   成功时 hilog 应见 `Native VPN bridge started.` 且无 SIGSEGV。

---

## 附：本机环境与工具

- OHOS Go 工具链：`/Users/liumin/Hey/build/native/ohos_golang_go/bin/go`（go1.24.5）。
- OHOS clang：`<DevEco>/sdk/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang`。
- 命令行打包：`<DevEco>/tools/hvigor/bin/hvigorw`（需 `NODE_HOME`、`DEVECO_SDK_HOME`）。
- hdc：`~/Library/OpenHarmony/Sdk/14/toolchains/hdc`（设备 `29Q0223920001682`）。
- 检查 .so 的 TLS 模型：`llvm-readelf -l <so> | grep TLS`（要有 PT_TLS）、
  `llvm-readelf -r <so> | grep TLSDESC`（要是 TLSDESC，不能是 TPREL/IE）。

---

## 9. 本次实现改动记录（2026-06-21）

### 9.1 方案落地概述

按路径 A（tun2socks 复活）实现，**用 OHOS Go fork（TLSDESC）重编两个 Go 库**，
数据面改为 `TUN fd → libheytun2socks.so → Xray 的 SOCKS 入站 → outbound`：

- **TLS 墙**：两个 .so 都用 OHOS go1.24.5 fork（`GOOS=openharmony`）编，产物带
  `PT_TLS + R_AARCH64_TLSDESC`，musl 下可 dlopen、外来线程 cgo 不再 SIGSEGV。
- **TUN fd 读取**：tun2socks 用的 gvisor 和 libxray 一样要打 `isSocketFD` 跳过
  `Fstat` 的补丁（Harmony VPN fd 拒绝 Fstat），否则 `engine.Start()` 会 `log.Fatal`
  退出进程。

真机结果（ALN-AL80 / HarmonyOS 6.1）：原"VPN 扩展没有回写启动完成状态"的崩溃
**已解决**，VPN 能连上、能上网（数据面通）。

### 9.2 源码改动清单（本次）

| 文件 | 改动 |
|---|---|
| `cpp/napi_init.cpp` | `#include <thread>`；新增 tun2socks 类型/全局（独立 handle `g_tun2socksHandle`）；`LoadXrayCore` 不再强求 `CGoSetTunFd`（SOCKS 路不需要）；新增 `LoadTun2SocksCore`（dlopen `libheytun2socks.so`）；`GetStats` 用适配器字节刷新流量；新增 `StartTun2Socks`/`StopTun2Socks` 并在 `Init` 注册 |
| `cpp/CMakeLists.txt` | foreach 拷贝列表加 `libheytun2socks.so` |
| `cpp/types/libheyvpn/Index.d.ts` | 加 `startTun2Socks`/`stopTun2Socks` 声明 |
| `cpp/prebuilt/arm64-v8a/libxray.so` | 替换为 **SOCKS 入站版**（xray-core v1.250803.0 + OHOS fork，TLSDESC）；导出仅 `CGoRunXrayFromJSON/CGoStopXray/CGoPing/CGoQueryStats` |
| `cpp/prebuilt/arm64-v8a/libheytun2socks.so` | **新增**（xjasonlyu/tun2socks v2.6.0 + OHOS fork，TLSDESC，含 gvisor Fstat 补丁） |
| `ets/native/HeyNative.ets` | 加 `startNativeTun2Socks`/`stopNativeTun2Socks` 绑定 |
| `ets/core/XrayConfig.ets` | 加 `VPN_DATA_SOCKS_HOST=127.0.0.1` / `VPN_DATA_SOCKS_PORT=10810`；VPN 数据面入站由 `protocol:'tun'` 改为 **`protocol:'socks'`**（tag 仍 `tun-in`，路由不动） |
| `ets/vpn/HeyVpnAbility.ets` | 删 `testNativeXrayConfig` preflight；Xray 路改为 `startNativeXray(socks)` 后 `startNativeTun2Socks(tunFd, 127.0.0.1, 10810, mtu)`；`cleanup` 加 `stopNativeTun2Socks`；sing-box 路暂保持原生 TUN 不变 |
| `docs/harmonyos-go-tls-wall.md` | 新增本排查/方案文档 |

> 注：`ShareLinkParser.ets` / `SubscriptionDetail.ets` / `SubscriptionEdit.ets` /
> `QrScan.ets` 是并行的其它改动（扫码/分享链接），**不属于本次 VPN 修复**。

### 9.3 ⚠️ 临时诊断改动（待回退）

为排查数据面加的临时代码，**确认稳定后要删**：

- `XrayConfig.ets`：`XrayLogConfig` 的 `access?`/`error?` 字段；VPN config 的
  `log` 段写死了 `loglevel:'debug'` + 落盘 `xray_error.log`/`xray_access.log`。
  应还原为 `loglevel: normalizeV2rayNgCoreLogLevel(settings?.logLevel ?? DEFAULT_LOG_LEVEL, ...)`。
- `HeyVpnAbility.ets`：`import fs`、`precreateDiagnosticLogs()` 方法及其调用、`[临时诊断]` 注释。

### 9.4 .so 构建方式（脚本尚未更新，先记命令）

构建产物与工具链在 **`~/hey-ohos-build/`**（仓库外，避免被 `hvigor clean` 删——
**教训：`hvigor clean` 会删除 `<repo>/build/`，native 产物不能放那里**）。

OHOS Go 工具链：`git clone --branch release-branch.go1.24 https://gitcode.com/openharmony-sig/ohos_golang_go.git`，
`cd src && GOROOT_BOOTSTRAP=/usr/local/go GOTOOLCHAIN=local ./make.bash`。

公共构建环境：
```
FORK=~/hey-ohos-build/ohos_golang_go
CC=<DevEco>/sdk/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang
公共 env：CGO_ENABLED=1 GOOS=openharmony GOARCH=arm64 CC=$CC CXX=${CC}++ \
         CGO_CFLAGS="-ftls-model=global-dynamic" GOTOOLCHAIN=local
注意：openharmony 的 net 端口需要 cgo，**不能加 `-tags netgo`**（会报 _C_getifaddrs undefined）。
```

- **libheytun2socks.so**：源码取自 `git show 5a21b4e^:entry/src/main/cpp/tun2socks_adapter/{go.mod,go.sum,main.go}`；
  把 gvisor 复制一份、patch `pkg/tcpip/link/fdbased/endpoint.go` 的 `isSocketFD` 为
  `return false, nil`，`go mod edit -replace gvisor.dev/gvisor=<patched>`；
  `go build -buildmode=c-shared -o libheytun2socks.so .`。
- **libxray.so（SOCKS 版）**：libXray 源取 `git -C <libXray全history> archive 20d70a98`（2025-08，go.mod 钉 xray-core v1.250803.0）；
  `go mod edit -go=1.24`；复制 `build/template/main.go` 到根并把根目录 `package libXray`→`package main`；
  version-script 只导出 `CGoRunXrayFromJSON;CGoStopXray;CGoPing;CGoQueryStats`；
  `go build -buildmode=c-shared -ldflags="... -checklinkname=0 -linkmode external ..." -o libxray.so .`。

### 9.5 待办

1. **回退 9.3 的临时诊断改动**。
2. 把 9.4 的构建写进 `scripts/build_libxray_ohos.sh`（加 `openharmony` 分支：fork + 去 netgo + 钉 v1.250803.0 + SOCKS exports）和恢复 `scripts/build_tun2socks_ohos.sh`（fork + gvisor 补丁）。
   - **2026-06-22 更新**：9.4 的 libxray 配方已**实测可复现**——用 `~/hey-ohos-build/ohos_golang_go`（go1.24.6 fork）
     + libXray @ `20d70a98` + `build/template/main.go`，编出过体积/导出/TLSDESC 与现役 .so 一致的产物
     （当时还试加了 `CGoPingBatch` 导出，后因改走纯 ArkTS 流式测速而弃用、还原原版 .so，见 bug-plan BUG-001）。
     脚本化（写进 `build_libxray_ohos.sh` 的 openharmony 分支）仍待补。
3. 出干净正式版重新装机确认（含 `device_vpn_smoke_test.sh`）。
4. 复核稳定性（首连冷启动是否偶发不通 / DNS-over-UDP 是否需加固）。
5. sing-box 核迁移到同方案（OHOS fork 重编 + 走 SOCKS 入站）——后续。
