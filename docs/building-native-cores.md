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

> 这是“怎么从源码构建这四个库”的权威说明（single source of truth）。
> **为什么必须这么编**的深度原理见 [`harmonyos-go-tls-wall.md`](harmonyos-go-tls-wall.md)。

---

## 1. 为什么是 OHOS Go fork + `GOOS=openharmony`

HarmonyOS 是 **musl** libc（`ld-musl-aarch64.so.1`）。Go 在 arm64 上怎么存 goroutine 指针 `g`（线程本地存储 TLS），决定了 c-shared 库能不能被 `dlopen`、外来线程（ArkTS/VPN）能不能调 cgo：

| 编法 | `g` 存哪 | 在 HarmonyOS(musl) 上的结果 |
| --- | --- | --- |
| 标准 Go + `GOOS=android` | bionic 固定 TLS 槽 | `dlopen` 能过，但外来线程那个槽是垃圾 → cgo→Go **SIGSEGV** |
| 标准 Go + `GOOS=linux` | initial-exec TLS | musl **拒绝 dlopen** 含 IE-TLS 的库 → 整个原生桥加载失败 |
| **OHOS fork + `GOOS=openharmony`** | **TLSDESC（通用动态 TLS）** | `dlopen` 能过 **且** 外来线程 cgo 正常 ✅ |

fork 给 arm64 补了 **TLSDESC**，产物带真正的 `PT_TLS` + `R_AARCH64_TLSDESC`。这是目前真机上唯一不崩的编法，三个 Go 库现役产物（`strings` 可见 `GOOS=openharmony`）都走这条路线。

**工具链版本**：现役是 [star4277/ohos-go](https://github.com/star4277/ohos-go) **v1.26.5-beta1**（go1.26.5）。它是在 openharmony-sig 的 OHOS go1.24 树上 merge go1.26.5 得到的第三方 fork，同样带 `openharmony` 端口 + arm64 TLSDESC。早先用的 openharmony-sig 官方 fork 封顶 **go1.24.5**，编不动需要 go1.26 的 libXray 主线，libxray 只能钉在 2025-08 的旧核；换成 go1.26.5 工具链后才升到 libXray **v26.7.28**（见 §3.1）。

> 这是第三方 fork：“能编”不等于“真机不崩”。换工具链或升级版本后，必须按 §4 确认 `PT_TLS` + `R_AARCH64_TLSDESC`，并在真机上验证外来线程（ArkTS / VPN 扩展）调 cgo 不 SIGSEGV。

---

## 2. 准备工具链

### 2.1 OHOS Go 工具链（一次性）

```bash
git clone --branch v1.26.5-beta1 https://github.com/star4277/ohos-go.git ~/hey-ohos-build/ohos-go-1.26.5
cd ~/hey-ohos-build/ohos-go-1.26.5/src
GOROOT_BOOTSTRAP=/usr/local/go GOTOOLCHAIN=local ./make.bash
```

- 自举需要 **go1.24.6+**（`src/cmd/dist/buildtool.go` 的 `minBootstrap`），`GOROOT_BOOTSTRAP` 指向本机任一满足版本的标准 Go。
- 编完确认：`bin/go version` 是 `go1.26.5`，`bin/go tool dist list | grep openharmony` 能看到 `openharmony/arm64`。
- 放在**仓库外**，默认约定路径 `~/hey-ohos-build/ohos-go-1.26.5`；三个 Go 脚本都用环境变量 `OHOS_GO_FORK` 覆盖。

> 旧的 openharmony-sig go1.24.5 fork（`~/hey-ohos-build/ohos_golang_go`）编不动 libXray v26.7.28，最多只能拿来回退编旧核，不再是默认工具链。

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

- libXray 源**钉死**在 tag **`v26.7.28`**（`LIBXRAY_PIN` 可覆盖；设 `LIBXRAY_SRC` 可改用本地源码目录），其 `go.mod` 声明 go1.26.3，锁 2026-07-28 的 xray-core（`v1.260327.1-0.20260728075948-5ca6f4b7d4dc`）。go1.26.5 工具链直接编，**不再**需要 `go mod edit -go=…` 降级。
- c-shared 入口是 libXray 自带的 **`cgo_bridge/`**（已是 `package main`），脚本执行 `go build ./cgo_bridge`；旧版“拷 `main.gotemplate` + 改 package 名”的步骤已删除。找不到 `cgo_bridge/main.go` 就报错退出（说明 libXray 版本太旧，需 v26.7.28+）。
- version-script **只导出 2 个符号**，其余全部被 `local: *` 隐藏：
  - `CGoInvoke(jsonRequest)`：单一分发入口。请求信封是 `{"apiVersion":1,"method":"…","payload":{…}}`，method 列表见 libXray 的 `invoke_model.go`（`runXrayFromJson` / `stopXray` / `ping` / `pingBatch` / `xrayVersion` / `getFreePorts` / `countGeoData` …）；返回原始 JSON（不是 base64）`{"success":…,"data":…,"error":"…"}`。
  - `CGoFree`：释放 `CGoInvoke` 返回的字符串。必须用它，不能用 `std::free`。
- 不导出 `CGoSetTunFd`：数据面走 tun2socks，libxray 只提供本地 SOCKS 入站和测速。napi 桥目前通过 `CGoInvoke` 调 `runXrayFromJson` / `stopXray` / `ping`。旧版遗留的可选符号（`CGoQueryStats` / `CGoCountGeoData` …）`dlsym` 拿到的是空指针，桥会优雅降级（例如流量统计回退到桥自身的计数）。
- 新版 run / ping 请求里不再带 datDir，Geo 资源目录只能通过环境变量 `XRAY_LOCATION_ASSET` 传给 Go，而且必须在首次 `dlopen` 之前设好，见 §5。
- gvisor `isSocketFD` 的 Fstat 补丁改为**尽力而为**（SOCKS 版通常不命中，不中只告警不中断）。
- 顺带把内置 Xray 核版本号戳进 `entry/src/main/ets/core/CoreInfo.ets`（`BUNDLED_XRAY_VERSION`），About 页用它显示，避免运行时原生冷调用。

脚本已收敛为单一 openharmony 路线；旧的 `GOOS_TARGET=android` 分支（在新版 HarmonyOS 上 cgo→Go 必崩）已从脚本删除，「为什么不用 android / linux」的取舍只保留在脚本顶部注释里。

### 3.2 libsingbox.so

```bash
bash scripts/build_libsingbox_ohos.sh
```

脚本要点（[`scripts/build_libsingbox_ohos.sh`](../scripts/build_libsingbox_ohos.sh)）：

- 源码是仓库内第一方 wrapper [`libsingbox/`](../libsingbox)（不 clone 外部仓库），`go.mod` 钉 **sing-box v1.12.25**（anytls 出站需要 1.12+）。用同一套 go1.26.5 工具链编译，wrapper 代码不用改。
- 导出 `CGoStartSingBox` / `CGoStopSingBox` / `CGoSetTunFd` / `CGoSingBoxVersion`。
- build tags 默认 `with_gvisor with_utls with_clash_api with_quic`，可用 `GO_TAGS` 覆盖。缺 `with_utls` → reality/uTLS 配置被拒；缺 `with_clash_api` → `libbox.NewService` 起不来；缺 `with_quic` → TUIC / Hysteria2 出站没注册，启动报 `QUIC is not included in this build`。**同样不能加 netgo**。
- 升到 sing-box 1.13 要重写 wrapper：libbox 删掉了 `NewService` / `BoxService`，改成 daemon + CommandServer 模型。所以暂时停在 1.12.25。
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

# 1) 确是 openharmony 产物，且用 go1.26.5 工具链编
strings -a "$SO" | grep -m1 'GOOS=openharmony'
strings -a "$SO" | grep -m1 -o 'go1\.26\.[0-9]*'   # go1.26.5

# 2) libxray 应只见 2 个 global 导出
llvm-nm -D "$SO" | grep ' T .*CGo'
#   CGoFree / CGoInvoke

# 3) 钉定的 xray-core 版本（libXray v26.7.28 对应 2026-07-28 的 pseudo-version）
strings -a "$SO" | grep -m1 -o 'xray-core@v[^ ]*'
#   xray-core@v1.260327.1-0.20260728075948-5ca6f4b7d4dc

# 4) TLSDESC 落地（fork 路线的关键标志）
llvm-readelf -l "$SO" | grep -i TLS          # 应有 PT_TLS
llvm-readelf -r "$SO" | grep -i TLSDESC       # 应有 R_AARCH64_TLSDESC
```

`llvm-nm` / `llvm-readelf` 在 DevEco 的 `<OHOS_NATIVE_HOME>/llvm/bin/` 下。其余两个 Go 库同样检查：`libsingbox.so` 应见 `CGoStartSingBox` / `CGoStopSingBox` / `CGoSetTunFd` / `CGoSingBoxVersion`，`strings` 应含 `sing-box@v1.12.25`；`libheytun2socks.so` 应见 4 个 `HeyTun2Socks*`（无 version-script，另有一批 cgo 运行时符号，属正常）。

`entry/src/main/cpp/prebuilt/arm64-v8a/*.h` 是 cgo 顺带生成的头文件，列的是全部 `//export` 符号，不管 version-script 有没有把其中一部分隐藏；手动替换 `.so` 时也可能忘了同步。判断导出集请以 `llvm-nm -D` 为准，不要信 `.h`。

---

## 5. 原生桥加载约束：`dlopen` 之后不要再 `setenv`

libXray v26.7.28 的 run / ping 请求不再带 datDir，Geo 资源目录只能靠环境变量 `XRAY_LOCATION_ASSET` 告诉 Go。napi 桥（[`napi_init.cpp`](../entry/src/main/cpp/napi_init.cpp) 的 `PrepareXrayAssetDir`）负责设置它，规则只有一条：**必须在首次 `dlopen` libxray.so 之前 `setenv`；任何 Go c-shared 库加载之后，都不能再调 `setenv`**。

原因有两层：

1. **Go 只在运行时初始化时拷贝一次 `environ`**。`dlopen` 之后 C 侧再 `setenv`，Go 根本看不到新值，Geo 资源目录就丢了。
2. **c-shared 运行时在 `dlopen` 返回后另起线程异步初始化**，初始化期间会读 `dlopen` 时捕获的 musl `environ` 数组。这时 C 侧 `setenv`，musl 会 realloc / free 旧数组，Go 初始化线程读到野指针，直接 SIGSEGV。这正是迁移到 libXray v26.7.28 后 VPN 扩展进程启动 Xray 就崩的真因：崩在非主线程（Go 线程），和 TLS 墙、工具链都无关。

因此 `PrepareXrayAssetDir` 用互斥锁保护，只在 `g_xrayHandle == nullptr`（库还没加载）时 `setenv` 一次，由 `StartXray` / `PingOutbound` 在首次加载核心前调用。以后给 napi 桥加代码时：

- 需要传给 Go 的环境变量，一律放到对应库首次 `dlopen` **之前**设置；
- 这条规则适用于所有 Go c-shared 库（libxray / libsingbox / libheytun2socks）：同进程里任一 Go 库加载后，`environ` 就可能正被它的初始化线程读取；
- 运行期要传的参数走调用参数（JSON 请求、函数实参），不要走环境变量。

> 现状的一处缺口：`PrepareXrayAssetDir` 只检查 libxray 自己有没有加载。如果同一进程里先加载过 libsingbox / libheytun2socks（例如先用 sing-box 连过、再切回 Xray），它仍会 `setenv` 一次。那时那些库的异步初始化通常早已结束，风险很低，但严格说不满足上面的规则，改这块时留意。

---

## 6. 雷区速查

- **产物/工具链放仓库外**（`~/hey-ohos-build/`），别放 `<repo>/build/`（`hvigor clean` 会删）。
- **不加 netgo**（openharmony net 需 cgo）。
- libxray 钉 **v26.7.28**，要用 go1.26.5 工具链编；旧 go1.24.5 fork 编不动。升级 `LIBXRAY_PIN` 前先确认 `cgo_bridge/` 入口和 `CGoInvoke` 的 method 名没变，否则要同步改 `napi_init.cpp`。
- **Go 库 `dlopen` 之后不要再 `setenv`**（§5）：要传给 Go 的环境变量只能在首次加载前设，否则轻则 Go 读不到，重则 SIGSEGV。
- 维护者若无 OHOS NDK / fork 环境，**改脚本后无法本机验证编译**，需在装好 fork 的机器实跑并按 §4 比对产物。
- `go.mod` 里**不能残留** `go mod edit -replace` 的机器绝对路径（gvisor 补丁路径），脚本结束会 `-dropreplace` 清理；提交前确认 `go.mod` 干净。
