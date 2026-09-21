#!/usr/bin/env bash
set -euo pipefail

# 交叉编译 Xray 内核为 HarmonyOS 的 libxray.so。
#
# 走 **OHOS 官方 Go fork + GOOS=openharmony**（与 build_libsingbox_ohos.sh 同一套
# 配方），这是目前真机上唯一不崩的编法，详见 docs/building-native-cores.md。
#
# ┌─ GOOS 选择：一段曾经的“两难”，现已由 OHOS Go fork 终结 ───────────────────────────┐
# │ HarmonyOS 是 musl libc（ld-musl-aarch64.so.1）。Go 在 arm64 上怎么存 goroutine     │
# │ 指针 g，决定了 c-shared 库能不能 dlopen、外来线程能不能调 cgo：                      │
# │                                                                                    │
# │  * 标准 Go + GOOS=android（已弃用）：g 存在 bionic 固定 TLS 槽（#16，纯 DATA 无 TLS │
# │    重定位）。dlopen 能过，但该槽在 OHOS-musl 上非 Go 创建的线程里是垃圾——每次从     │
# │    ArkTS/UI 线程 cgo→Go 都 SIGSEGV。真机实测连 VPN 扩展线程也已踩爆，故已彻底放弃。  │
# │  * 标准 Go + GOOS=linux：g 是真 ELF TLS（TPIDR_EL0），但带 initial-exec 重定位，     │
# │    musl 拒绝在 dlopen 的库里用 IE-TLS → 整个原生桥加载失败。                         │
# │  * OHOS Go fork + GOOS=openharmony（本脚本采用）：fork 给 arm64 补了 TLSDESC        │
# │    （通用动态 TLS）。产物带真正的 PT_TLS + R_AARCH64_TLSDESC，musl 能 dlopen，      │
# │    外来线程 cgo 也不再读到垃圾 g。这是真正的解。                                      │
# │                                                                                    │
# │ 工具链已从 openharmony-sig 的 go1.24.5 fork 换成 star4277/ohos-go v1.26.5-beta1     │
# │ （go1.26.5，同样带 openharmony 端口 + arm64 TLSDESC），解锁 libXray 主线            │
# │ （v26.7.28 需 go1.26.3）。数据面仍走 tun2socks（libxray 只提供 SOCKS 入站与诊断，   │
# │ 不启用原生 TUN），故不导出 CGoSetTunFd；新版 API 改为单一 CGoInvoke 分发入口。      │
# └────────────────────────────────────────────────────────────────────────────────────┘
#
# 用法：bash scripts/build_libxray_ohos.sh
#
# ⚠️ 无 OHOS NDK / go 工具链时无法本机验证编译；改动后请在装好工具链的环境实跑，
#    并比对产物：nm -D 应只见 CGoInvoke/CGoFree 两个 global 符号、strings 应含
#    xray-core@v1.2607xx（新核）、readelf -r 应有 R_AARCH64_TLSDESC。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-${SDK_HOME}/default/openharmony/native}"
CC_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
WORK_DIR="${ROOT_DIR}/build/native/libxray-ohos"
SRC_DIR="${WORK_DIR}/src"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"
LIBXRAY_REPO="${LIBXRAY_REPO:-https://github.com/XTLS/libXray.git}"
EXPORTS_FILE="${WORK_DIR}/libxray.exports"
GO_LDFLAGS_DEFAULT="-s -w -checklinkname=0 -linkmode external -extldflags \"-Wl,--version-script=${EXPORTS_FILE} -Wl,-z,lazy\""

# OHOS Go 工具链（star4277/ohos-go v1.26.5-beta1，go1.26.5，带 openharmony 端口 + TLSDESC）
# 与钉定的 libXray 版本。老 go1.24.5 fork（openharmony-sig）已封顶、编不动新核，
# 换 go1.26 工具链后解锁 libXray 主线。覆盖请设 OHOS_GO_FORK / LIBXRAY_PIN。
OHOS_GO_FORK="${OHOS_GO_FORK:-${HOME}/hey-ohos-build/ohos-go-1.26.5}"
LIBXRAY_PIN="${LIBXRAY_PIN:-v26.7.28}"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"
rm -rf "${SRC_DIR}"

# ── 工具链：OHOS Go fork ───────────────────────────────────────────────────────────
if [[ -x "${OHOS_GO_FORK}/bin/go" ]]; then
  export PATH="${OHOS_GO_FORK}/bin:${PATH}"
  export GOTOOLCHAIN=local
else
  echo "ERROR: 找不到 OHOS Go fork: ${OHOS_GO_FORK}/bin/go" >&2
  echo "  按 docs/building-native-cores.md 构建该工具链：" >&2
  echo "  git clone --branch release-branch.go1.24 https://gitcode.com/openharmony-sig/ohos_golang_go.git" >&2
  echo "  cd ohos_golang_go/src && GOROOT_BOOTSTRAP=/usr/local/go GOTOOLCHAIN=local ./make.bash" >&2
  exit 1
fi
# 去掉其余 IE-TLS 重定位，配合 fork 的 tls_g TLSDESC——musl 在 dlopen 的库里只接受
# 通用动态 TLS（global-dynamic / TLSDESC），不接受 initial-exec。
export CGO_CFLAGS="${CGO_CFLAGS:-} -ftls-model=global-dynamic"
# ⚠️ 不能加 netgo：openharmony 的 net 端口需要 cgo，加了会报 _C_getifaddrs undefined。
GO_TAGS="${GO_TAGS:-}"

# ── 导出符号 ──────────────────────────────────────────────────────────────────────
# libXray v26.7.28 起改为单一分发入口：所有方法经 CGoInvoke(jsonRequest) 路由
# （method 见 invoke_model.go：ping/pingBatch/runXray/runXrayFromJson/stopXray/
# xrayVersion/getXrayState/getFreePorts/countGeoData…），CGoFree 释放返回串。
# 故只导出这两个符号；其余被 version-script 的 local:* 隐藏。
cat > "${EXPORTS_FILE}" <<'MAP'
{
  global:
    CGoInvoke;
    CGoFree;
  local: *;
};
MAP

# ── 取 libXray 源码 ───────────────────────────────────────────────────────────────
if [[ -n "${LIBXRAY_SRC:-}" ]]; then
  cp -R "${LIBXRAY_SRC}" "${SRC_DIR}"
else
  # 需 checkout 历史提交 ${LIBXRAY_PIN}，浅克隆默认只有 HEAD，故全量 clone 再 checkout。
  git clone "${LIBXRAY_REPO}" "${SRC_DIR}"
  git -C "${SRC_DIR}" checkout "${LIBXRAY_PIN}"
fi

cd "${SRC_DIR}"

# libXray v26.7.28 起：c-shared 入口在 cgo_bridge/（已是 package main，导出
# CGoInvoke/CGoFree），不再需要旧版 main.gotemplate 拷贝 + package 改名。
# go.mod 声明 go1.26.3，新工具链（go1.26.5）可直接编，无需降级 go 版本。
if [[ ! -f cgo_bridge/main.go ]]; then
  echo "ERROR: 未找到 ${SRC_DIR}/cgo_bridge/main.go（libXray 版本过旧？需 v26.7.28+）" >&2
  exit 1
fi

# ── gvisor fdbased Fstat 补丁（尽力而为）────────────────────────────────────────────
# gvisor 的 fdbased 端点用 unix.Fstat 判断 dispatcher，而 HarmonyOS 的 VPN fd 会拒 Fstat
# （readv/writev 正常）。现役 libxray 是“SOCKS 版”（数据面走 tun2socks，不再用核心自带的
# TUN 入站），通常不命中此处；但钉死的旧版若仍引用，则需此补丁。故改为尽力而为：补丁不中
# 只告警、不中断。
GVISOR_MODULE_VERSION="$(go list -m -f '{{.Version}}' gvisor.dev/gvisor 2>/dev/null || true)"
if [[ -n "${GVISOR_MODULE_VERSION}" ]]; then
  GVISOR_MODULE_DIR="$(go env GOMODCACHE)/gvisor.dev/gvisor@${GVISOR_MODULE_VERSION}"
  if [[ ! -d "${GVISOR_MODULE_DIR}" ]]; then
    go mod download gvisor.dev/gvisor || true
  fi
  FDBASED_GO="${GVISOR_MODULE_DIR}/pkg/tcpip/link/fdbased/endpoint.go"
  if [[ -f "${FDBASED_GO}" ]] && grep -q 'func isSocketFD(fd int)' "${FDBASED_GO}"; then
    PATCHED_GVISOR_DIR="${WORK_DIR}/gvisor-patched"
    [[ -d "${PATCHED_GVISOR_DIR}" ]] && chmod -R u+w "${PATCHED_GVISOR_DIR}"
    rm -rf "${PATCHED_GVISOR_DIR}"
    cp -R "${GVISOR_MODULE_DIR}" "${PATCHED_GVISOR_DIR}"
    chmod -R u+w "${PATCHED_GVISOR_DIR}"
    python3 - "${PATCHED_GVISOR_DIR}/pkg/tcpip/link/fdbased/endpoint.go" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = """func isSocketFD(fd int) (bool, error) {
\tvar stat unix.Stat_t
\tif err := unix.Fstat(fd, &stat); err != nil {
\t\treturn false, fmt.Errorf("unix.Fstat(%v,...) failed: %v", fd, err)
\t}
\treturn (stat.Mode & unix.S_IFSOCK) == unix.S_IFSOCK, nil
}
"""
new = """func isSocketFD(fd int) (bool, error) {
\t// HarmonyOS VPN fd 会拒 Fstat（但 readv/writev 正常），强制走可移植的
\t// 非 socket Readv dispatcher，绕开 Fstat。
\treturn false, nil
}
"""
if old not in text:
    print("WARN: isSocketFD 实现与预期不符，跳过 gvisor 补丁（SOCKS 版通常不需要）", file=sys.stderr)
else:
    path.write_text(text.replace(old, new))
    print("Patched gvisor isSocketFD")
PY
    go mod edit -replace="gvisor.dev/gvisor=${PATCHED_GVISOR_DIR}"
  else
    echo "WARN: 未在 gvisor 找到 fdbased/isSocketFD，跳过补丁（SOCKS 版通常不需要）" >&2
  fi
else
  echo "WARN: 依赖里未发现 gvisor 模块，跳过补丁。" >&2
fi

# ── 构建 ─────────────────────────────────────────────────────────────────────────
CGO_ENABLED=1 \
GOOS=openharmony \
GOARCH=arm64 \
CC="${CC_BIN}" \
CXX="${CXX_BIN}" \
go build \
  -tags "${GO_TAGS}" \
  -trimpath \
  -ldflags="${GO_LDFLAGS:-${GO_LDFLAGS_DEFAULT}}" \
  -buildmode=c-shared \
  -o "${OUT_DIR}/libxray.so" \
  ./cgo_bridge

# 撤掉构建期注入的 gvisor replace（若有），保持 SRC 干净。
go mod edit -dropreplace="gvisor.dev/gvisor" 2>/dev/null || true

echo "Built ${OUT_DIR}/libxray.so (GOOS=openharmony)"

# ── 把内置 Xray 核版本号戳进 CoreInfo.ets ───────────────────────────────────────────
# About 页直接显示这个常量，而不在运行时调原生 CGoXrayVersion()。该常量从所锁定的
# xtls/xray-core 源码（core/core.go 的 Version_x/y/z）读取，与 prebuilt .so 同步。
# 历史上 GOOS=android 的库冷调 CGoXrayVersion 会 SIGSEGV；openharmony(fork) 路线已无此问题，
# 但保留“构建期戳常量”做法仍可避免一次原生冷调用，且更省事。
CORE_INFO_FILE="${ROOT_DIR}/entry/src/main/ets/core/CoreInfo.ets"
XRAY_CORE_DIR="$(go list -m -f '{{.Dir}}' github.com/xtls/xray-core 2>/dev/null || true)"
CORE_GO="${XRAY_CORE_DIR}/core/core.go"
if [[ -n "${XRAY_CORE_DIR}" && -f "${CORE_GO}" ]]; then
  VX="$(grep -E 'Version_x[[:space:]]+byte' "${CORE_GO}" | grep -oE '[0-9]+' | head -1)"
  VY="$(grep -E 'Version_y[[:space:]]+byte' "${CORE_GO}" | grep -oE '[0-9]+' | head -1)"
  VZ="$(grep -E 'Version_z[[:space:]]+byte' "${CORE_GO}" | grep -oE '[0-9]+' | head -1)"
else
  VX=""; VY=""; VZ=""
fi
if [[ -n "${VX}" && -n "${VY}" && -n "${VZ}" ]]; then
  XRAY_VER="${VX}.${VY}.${VZ}"
  if [[ -f "${CORE_INFO_FILE}" ]] && grep -q 'export const BUNDLED_XRAY_VERSION' "${CORE_INFO_FILE}"; then
    python3 - "${CORE_INFO_FILE}" "${XRAY_VER}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text()
next_text, count = re.subn(
    r"export const BUNDLED_XRAY_VERSION: string = '[^']*';",
    f"export const BUNDLED_XRAY_VERSION: string = '{version}';",
    text,
    count=1,
)
if count != 1:
    raise SystemExit("BUNDLED_XRAY_VERSION export not found")
path.write_text(next_text)
PY
  else
    cat > "${CORE_INFO_FILE}" <<EOF
/**
 * 内置 Xray 内核（xtls/xray-core）的版本号 —— 即 \`core.Version()\` 的返回值。
 *
 * 此常量在重新编译 libxray.so 时由 scripts/build_libxray_ohos.sh 从所锁定的
 * xtls/xray-core 源码（core/core.go 的 Version_x/y/z 常量）自动写入，
 * 与 prebuilt/arm64-v8a/libxray.so 保持同步——请勿手动修改。
 */
export const BUNDLED_XRAY_VERSION: string = '${XRAY_VER}';
EOF
  fi
  echo "Stamped bundled Xray core version ${XRAY_VER} into ${CORE_INFO_FILE}"
else
  echo "WARN: could not parse Xray core version from ${CORE_GO}; left CoreInfo.ets unchanged" >&2
fi
