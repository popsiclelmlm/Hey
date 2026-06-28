# 构建原生内核库（libxray / libsingbox / libheytun2socks / libhevsocks5tun）

Hey 打包了四个 `.so`（前三个 Go，第四个 C）：

| 库 | 语言 | 作用 | 构建脚本 |
| --- | --- | --- | --- |
| `libxray.so` | Go | Xray 内核（默认内核），提供本地 SOCKS 入站 | `scripts/build_libxray_ohos.sh` |
| `libsingbox.so` | Go | sing-box 内核（可选第二内核），提供本地 SOCKS 入站 | `scripts/build_libsingbox_ohos.sh` |
| `libheytun2socks.so` | Go | 默认 tun2socks 引擎（gvisor/xjasonlyu），把 VPN TUN fd 的流量转发进核心的本地 SOCKS 入站 | `scripts/build_tun2socks_ohos.sh` |
| `libhevsocks5tun.so` | C | 可选 tun2socks 引擎（hev-socks5-tunnel），同样把 TUN fd 转发进本地 SOCKS 入站；「使用 Hev TUN 引擎」开关打开时启用 | `scripts/build_hev_ohos.sh` |

产物统一落在 `entry/src/main/cpp/prebuilt/arm64-v8a/`，由 CMake 在构建 `libheyvpn.so` 后拷进 HAP。

> `libheytun2socks.so`（gvisor，默认）与 `libhevsocks5tun.so`（hev，可选）是**同一数据面的
> 两套实现**，运行时由设置项 `useHevTun` 二选一，互斥。原生侧（`napi_init.cpp`）按当前引擎
> 分发 start/stop/stats，停止统一走 `stopTun2Socks`。

> 这是“怎么从源码构建这三个库”的权威说明（single source of truth）。
> **为什么必须这么编**的深度原理见 [`harmonyos-go-tls-wall.md`](harmonyos-go-tls-wall.md)。

---

## 1. 为什么是 OHOS Go fork + `GOOS=openharmony`

HarmonyOS 是 **musl** libc（`ld-musl-aarch64.so.1`）。Go 在 arm64 上怎么存 goroutine 指针 `g`（线程本地存储 TLS），决定了 c-shared 库能不能被 `dlopen`、外来线程（ArkTS/VPN）能不能调 cgo：

| 编法 | `g` 存哪 | 在 HarmonyOS(musl) 上的结果 |
| --- | --- | --- |
| 标准 Go + `GOOS=android` | bionic 固定 TLS 槽 | `dlopen` 能过，但外来线程那个槽是垃圾 → cgo→Go **SIGSEGV** |
| 标准 Go + `GOOS=linux` | initial-exec TLS | musl **拒绝 dlopen** 含 IE-TLS 的库 → 整个原生桥加载失败 |
| **OHOS fork + `GOOS=openharmony`** | **TLSDESC（通用动态 TLS）** | `dlopen` 能过 **且** 外来线程 cgo 正常 ✅ |

fork 给 arm64 补了 **TLSDESC**，产物带真正的 `PT_TLS` + `R_AARCH64_TLSDESC`。这是目前真机上唯一不崩的编法，三个库现役产物（`strings` 可见 `GOOS=openharmony`）都走这条路线。

**代价**：fork 目前封顶 **go1.24.5**，而 libXray 主线已需 go1.26、xray-core 需 go≥1.25。所以 libxray 必须钉回能用 go1.24 编的旧版（见 §3.1）。

---

## 2. 准备工具链

### 2.1 OHOS Go fork（一次性）

```bash
git clone --branch release-branch.go1.24 https://gitcode.com/openharmony-sig/ohos_golang_go.git
cd ohos_golang_go/src
GOROOT_BOOTSTRAP=/usr/local/go GOTOOLCHAIN=local ./make.bash
```

把整个 `ohos_golang_go/` 放在**仓库外**，默认约定路径 `~/hey-ohos-build/ohos_golang_go`（脚本用环境变量 `OHOS_GO_FORK` 覆盖）。

> ⚠️ **不要放进仓库的 `build/`**：`hvigor clean` 会删掉 `<repo>/build/`，曾因此丢过整套工具链。

### 2.2 DevEco Native（OHOS clang）

构建机需装 DevEco Studio / HarmonyOS SDK。三个脚本共用其中的交叉编译器：

```
CC  = <DevEco>/sdk/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang
CXX = 同上 + clang++
```

脚本默认从 `DEVECO_SDK_HOME`（缺省 `/Applications/DevEco-Studio.app/Contents/sdk`）推导，可用 `OHOS_NATIVE_HOME` 覆盖。

### 2.3 公共构建环境

三个库都用同一套 cgo 环境：

```
CGO_ENABLED=1 GOOS=openharmony GOARCH=arm64 \
CC=$CC CXX=${CC}++ \
CGO_CFLAGS="-ftls-model=global-dynamic" \
GOTOOLCHAIN=local
```

- `-ftls-model=global-dynamic`：去掉其余 initial-exec TLS 重定位，配合 fork 的 `tls_g` TLSDESC——musl 在 `dlopen` 的库里只接受通用动态 TLS。
- **不能加 `-tags netgo`**：openharmony 的 net 端口需要 cgo，加了会报 `_C_getifaddrs undefined`。

---

## 3. 各库构建

### 3.1 libxray.so

```bash
bash scripts/build_libxray_ohos.sh           # 默认 openharmony
```

脚本要点（[`scripts/build_libxray_ohos.sh`](../scripts/build_libxray_ohos.sh)）：

- libXray 源**钉死**在提交 `20d70a98`（2025-08，`LIBXRAY_PIN` 可覆盖），其 `go.mod` 锁 **xray-core v1.250803.0**——go1.24 能编。`go mod edit -go=1.24` 降语言版本以适配 fork。
- version-script **只导出 4 个 SOCKS 数据面符号**：`CGoRunXrayFromJSON` / `CGoStopXray` / `CGoPing` / `CGoQueryStats`。旧版模板天然**不含** `CGoSetTunFd`（原生 TUN 入站已弃用，数据面改走 tun2socks）；其余模板自带符号（`CGoXrayVersion`/`CGoInitDns`…）被 `local: *` 隐藏。
- gvisor `isSocketFD` 的 Fstat 补丁改为**尽力而为**（SOCKS 版通常不命中，不中只告警不中断）。
- 顺带把内置 Xray 核版本号戳进 `entry/src/main/ets/core/CoreInfo.ets`（`BUNDLED_XRAY_VERSION`），About 页用它显示，避免运行时原生冷调用。

脚本已收敛为单一 openharmony 路线；旧的 `GOOS_TARGET=android` 分支（在新版 HarmonyOS 上 cgo→Go 必崩）已从脚本删除，「为什么不用 android / linux」的取舍只保留在脚本顶部注释里。

### 3.2 libsingbox.so

```bash
bash scripts/build_libsingbox_ohos.sh
```

脚本要点（[`scripts/build_libsingbox_ohos.sh`](../scripts/build_libsingbox_ohos.sh)）：

- 源码是仓库内第一方 wrapper [`libsingbox/`](../libsingbox)（不 clone 外部仓库），钉 **sing-box v1.11.0**。
- 导出 `CGoStartSingBox` / `CGoStopSingBox` / `CGoSetTunFd` / `CGoSingBoxVersion`。
- build tags 必须有 `with_gvisor with_utls with_clash_api`（缺 `with_utls` → reality/uTLS 配置被拒；缺 `with_clash_api` → `libbox.NewService` 起不来）；**同样不能加 netgo**。
- gvisor `isSocketFD` 补丁同为尽力而为。

### 3.3 libheytun2socks.so

```bash
bash scripts/build_tun2socks_ohos.sh
```

脚本要点（[`scripts/build_tun2socks_ohos.sh`](../scripts/build_tun2socks_ohos.sh)）：

- 源码是仓库内第一方 adapter [`entry/src/main/cpp/tun2socks_adapter/`](../entry/src/main/cpp/tun2socks_adapter)（基于 xjasonlyu/tun2socks v2.6.0），`go.mod` 钉 gvisor `v0.0.0-20250523182742`。
- 导出 `HeyTun2SocksStart` / `HeyTun2SocksStop` / `HeyTun2SocksUploadBytes` / `HeyTun2SocksDownloadBytes`（后两个供流量统计）；无 version-script，4 个 `//export` 符号默认全导出。
- gvisor `isSocketFD` 的 Fstat 补丁是 **required**（不像 libxray 的 SOCKS 版那样尽力而为）：tun2socks 必把 TUN fd 交给 gvisor fdbased，HarmonyOS VPN fd 拒 Fstat，不打补丁 `engine.Start()` 会 `log.Fatal` 退出整个进程；补丁匹配不上即报错退出。
- 这是 VPN 数据面的命脉，两个内核都依赖它（见 §1 表）。
- 构建期会对 `tun2socks_adapter/go.mod` 注入 gvisor `replace`，脚本结尾 `go mod edit -dropreplace` 撤回——提交前确认 `go.mod` 不含机器绝对路径。

### 3.4 libhevsocks5tun.so

```bash
bash scripts/build_hev_ohos.sh
```

脚本要点（[`scripts/build_hev_ohos.sh`](../scripts/build_hev_ohos.sh)）：

- 源码是上游 [heiher/hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel)（含 `hev-task-system` / `yaml` 子模块），`HEV_PIN` 钉死版本（默认 `2.9.0`，可覆盖）。
- **纯 C，不走 Go fork**：hev 不碰 Go-on-musl 的 TLS 墙（[`harmonyos-go-tls-wall.md`](harmonyos-go-tls-wall.md)），用 DevEco 的 OHOS clang（`aarch64-unknown-linux-ohos-clang` + sysroot）直接 `--target=aarch64-linux-ohos` 交叉编译即可，**不需要 OHOS Go fork**。
- 先 `make static` 出静态库，再用 `clang -shared -Wl,--whole-archive` 把整个 `.a` 链成共享库，保留导出符号。
- 导出 3 个符号：`hev_socks5_tunnel_main_from_str`（阻塞，跑到 quit 才返回）/ `hev_socks5_tunnel_quit` / `hev_socks5_tunnel_stats`，由 `napi_init.cpp` 的 `LoadHevCore`/`StartHevTun`/`StopTun2Socks`/`GetStats` dlsym 调用。yaml 配置由 ArkTS 侧 [`HevTunConfig.ets`](../entry/src/main/ets/core/HevTunConfig.ets) 生成。
- ⚠️ 升级 `HEV_PIN` 前确认上游未改符号名或 yaml 字段（`tunnel.mtu` / `socks5.address|port|udp` / `misc.log-level|tcp-read-write-timeout|udp-read-write-timeout`）；若变了，需同步 `napi_init.cpp` 与 `HevTunConfig.ets`。
- 校验：`nm -D libhevsocks5tun.so | grep hev_socks5_tunnel` 应见 3 个符号。

---

## 4. 校验产物

构建后逐一确认（以 libxray 为例）：

```bash
SO=entry/src/main/cpp/prebuilt/arm64-v8a/libxray.so

# 1) 确是 openharmony 产物
strings -a "$SO" | grep -m1 'GOOS=openharmony'

# 2) libxray 应只见 4 个 global 导出
nm -D "$SO" | grep ' T .*CGo'
#   CGoPing / CGoQueryStats / CGoRunXrayFromJSON / CGoStopXray

# 3) 钉死的 xray-core 版本
strings -a "$SO" | grep -m1 'xray-core@v1.250803.0'

# 4) TLSDESC 落地（fork 路线的关键标志）
llvm-readelf -l "$SO" | grep -i TLS          # 应有 PT_TLS
llvm-readelf -r "$SO" | grep -i TLSDESC       # 应有 R_AARCH64_TLSDESC
```

`entry/src/main/cpp/prebuilt/arm64-v8a/libxray.h` 是 cgo 生成的旧产物头文件，**可能与现役 .so 不一致**（例如列了已不存在的 `CGoSetTunFd`），判断导出集请以 `nm -D` 为准，不要信 `.h`。

---

## 5. 雷区速查

- **产物/工具链放仓库外**（`~/hey-ohos-build/`），别放 `<repo>/build/`（`hvigor clean` 会删）。
- **不加 netgo**（openharmony net 需 cgo）。
- libxray **不能用主线**（要 go1.26），必须钉 go1.24 能编的旧版。
- 维护者若无 OHOS NDK / fork 环境，**改脚本后无法本机验证编译**，需在装好 fork 的机器实跑并按 §4 比对产物。
- `go.mod` 里**不能残留** `go mod edit -replace` 的机器绝对路径（gvisor 补丁路径），脚本结束会 `-dropreplace` 清理；提交前确认 `go.mod` 干净。
