#!/usr/bin/env bash
set -euo pipefail

# 交叉编译 hev-socks5-tunnel（C）为 HarmonyOS 的 libhevsocks5tun.so。
#
# 这是「使用 Hev TUN 引擎」开关打开时走的高性能数据面，对照默认的 gvisor/xjasonlyu
# 引擎（libheytun2socks.so，见 build_tun2socks_ohos.sh）。两者都干同一件事：读 Harmony
# VPN 的 TUN fd → 转发进内核的本地 SOCKS 入站（127.0.0.1:VPN_DATA_SOCKS_PORT）；只是
# 实现不同：hev 是纯 C 协程栈（hev-task-system + 内置 yaml），更轻更快。
#
# ✅ 与三个 Go 库不同：hev 是 **纯 C**，不碰 Go-on-musl 的 TLS 墙
#    （docs/harmonyos-go-tls-wall.md），用 DevEco 的 OHOS clang 直接交叉编译即可，
#    不需要 OHOS Go fork。
#
#    若无 OHOS NDK，改脚本后无法本机验证编译；请在装好 DevEco 的机器实跑，
#    并按 docs/building-native-cores.md §4 校验产物：
#      nm -D libhevsocks5tun.so | grep hev_socks5_tunnel
#    应见 3 个导出符号：hev_socks5_tunnel_main_from_str / _quit / _stats。
#    若 hev 上游改了符号名或 yaml 字段，需同步改 napi_init.cpp 与 HevTunConfig.ets。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-${SDK_HOME}/default/openharmony/native}"
CC_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
AR_BIN="${OHOS_NATIVE_HOME}/llvm/bin/llvm-ar"
RANLIB_BIN="${OHOS_NATIVE_HOME}/llvm/bin/llvm-ranlib"
SYSROOT="${OHOS_NATIVE_HOME}/sysroot"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"
WORK_DIR="${ROOT_DIR}/build/native/libhevsocks5tun-ohos"

# hev 上游与钉死版本。改版本前先确认符号名/yaml 字段未变（见脚本顶部 ⚠️）。
HEV_REPO="${HEV_REPO:-https://github.com/heiher/hev-socks5-tunnel.git}"
HEV_PIN="${HEV_PIN:-2.9.0}"

if [[ ! -x "${CC_BIN}" ]]; then
  echo "ERROR: 找不到 OHOS clang: ${CC_BIN}" >&2
  echo "  装好 DevEco Studio / HarmonyOS SDK，或用 OHOS_NATIVE_HOME 覆盖路径。" >&2
  exit 1
fi

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

# ── 拉源码（含子模块 hev-socks5-core / hev-task-system / lwip / yaml）─────────────────
SRC_DIR="${WORK_DIR}/src"
if [[ ! -d "${SRC_DIR}/.git" ]]; then
  git clone --recursive "${HEV_REPO}" "${SRC_DIR}"
fi
cd "${SRC_DIR}"
git fetch --tags --quiet
git checkout --quiet "${HEV_PIN}"
git submodule update --init --recursive

# ── 交叉编译 ────────────────────────────────────────────────────────────────────────
# OHOS 是 aarch64 + musl。hev 的 Makefile 接受 CC/CFLAGS；先出静态库，再整体链成共享库。
# 注意：不要加 -D_GNU_SOURCE —— hev-task-system 的源码自己 `#define _GNU_SOURCE`，命令行再传
# 会因 hev 的 -Werror=macro-redefined 直接编译失败。
COMMON_FLAGS="--target=aarch64-linux-ohos --sysroot=${SYSROOT} -fPIC -O2"

make clean >/dev/null 2>&1 || true
# `make static` 产出 bin/libhev-socks5-tunnel.a（库目标，含 hev_socks5_tunnel_* 公共 API）。
# 用 OHOS 的 llvm-ar/llvm-ranlib 打包，避免 macOS 宿主 ranlib 处理交叉 .a 报「空 TOC」警告。
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
  CC="${CC_BIN}" \
  AR="${AR_BIN}" \
  RANLIB="${RANLIB_BIN}" \
  CFLAGS="${COMMON_FLAGS}" \
  static

# 收集全树所有静态库：主库 libhev-socks5-tunnel.a 在根 bin/（含公共 API + 内置 lwip/yaml），
# 但 hev-task-system 等子模块各自编进自己的 bin/，不在根 bin/。必须把它们一起链进来，否则
# .so 会留下 hev_task_*/hev_object_*/hev_malloc 等未解析符号，真机 dlopen 时报 "symbol not
# found"（共享库默认允许未定义符号，主机链接不报错——靠后面的自检兜底）。
MAIN_LIB=""
OTHER_LIBS=()
while IFS= read -r a; do
  case "${a}" in
    */libhev-socks5-tunnel.a) MAIN_LIB="${a}" ;;
    *) OTHER_LIBS+=( "${a}" ) ;;
  esac
done < <(find "${SRC_DIR}" -name '*.a' -type f)
if [[ -z "${MAIN_LIB}" ]]; then
  echo "ERROR: 未找到主静态库 libhev-socks5-tunnel.a；hev 的 make 目标/产物路径可能变了，需人工适配。" >&2
  exit 1
fi

# --whole-archive 主库（保留 hev_socks5_tunnel_* 导出，.so 自身不引用这些入口符号）；
# 其余静态库（hev-task-system…）正常链接，按需解析主库引用的内部符号。重复符号不会冲突：
# 普通归档只为满足未解析符号而拉取对象，已定义的（如主库内置的 lwip）不会被二次拉入。
# `${OTHER_LIBS[@]+...}` 是 bash 3.2（macOS 自带）下空数组 + set -u 的安全展开写法。
# musl 上 pthread 已并入 libc，-lpthread 可有可无，留着兼容。
"${CC_BIN}" ${COMMON_FLAGS} -shared \
  -o "${OUT_DIR}/libhevsocks5tun.so" \
  -Wl,--whole-archive "${MAIN_LIB}" -Wl,--no-whole-archive \
  ${OTHER_LIBS[@]+"${OTHER_LIBS[@]}"} \
  -lpthread

# ── 自检：.so 不应再有未解析的 hev_/lwip 内部符号（漏链静态库的典型症状）─────────────
NM_BIN="${OHOS_NATIVE_HOME}/llvm/bin/llvm-nm"
[[ -x "${NM_BIN}" ]] || NM_BIN="nm"
LEFTOVER="$("${NM_BIN}" -D -u "${OUT_DIR}/libhevsocks5tun.so" 2>/dev/null \
  | grep -iE '\b(hev_|lwip_|pbuf_|netif_)' || true)"
if [[ -n "${LEFTOVER}" ]]; then
  echo "ERROR: libhevsocks5tun.so 仍有未解析的内部符号（漏链了某个 bin/*.a）：" >&2
  echo "${LEFTOVER}" >&2
  exit 1
fi

echo "Built ${OUT_DIR}/libhevsocks5tun.so (hev-socks5-tunnel ${HEV_PIN})"
echo "导出符号校验：${NM_BIN} -D '${OUT_DIR}/libhevsocks5tun.so' | grep hev_socks5_tunnel"
