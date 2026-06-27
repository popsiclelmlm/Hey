#!/usr/bin/env bash
set -euo pipefail

# 交叉编译 sing-box 内核为 HarmonyOS 的 libsingbox.so（Phase 0 spike）。
#
# 工具链与 GOOS 选择完全照搬 scripts/build_libxray_ohos.sh —— 那套已在本项目验证
# 可行（dlopen 不被 musl 拒、VPN 线程里 cgo 可跑）。这里只换成第一方的
# libsingbox/ wrapper（不 clone 外部仓库）。
#
# 与 libxray 脚本的差异，都在标了 [SING-BOX] 的注释里：
#   1. 源码是仓库内的 libsingbox/，先 go mod tidy 拉齐 sing-box 依赖；
#   2. 导出符号换成 CGoStartSingBox/CGoStopSingBox/CGoSetTunFd/CGoSingBoxVersion；
#   3. build tags 需要 with_gvisor（tun 的 gvisor 协议栈）；
#   4. gvisor 的 Fstat patch 改为「尽力而为」：sing-box 经 sing-tun 走 sagernet 的
#      gvisor fork，是否命中同一处 isSocketFD 需在设备上确认，patch 不中只告警不中断。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-${SDK_HOME}/default/openharmony/native}"
CC_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
WORK_DIR="${ROOT_DIR}/build/native/libsingbox-ohos"
# [SING-BOX] 源码是仓库内第一方 wrapper，不 clone。
SRC_DIR="${ROOT_DIR}/libsingbox"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"
EXPORTS_FILE="${WORK_DIR}/libsingbox.exports"
GO_LDFLAGS_DEFAULT="-s -w -checklinkname=0 -linkmode external -extldflags \"-Wl,--version-script=${EXPORTS_FILE} -Wl,-z,lazy\""

# [SING-BOX] 用 OHOS 官方 Go fork + GOOS=openharmony 编译——这是 docs/harmonyos-go-tls-wall.md
# 定的正解。fork 为 arm64 补了 TLSDESC（通用动态 TLS）：产物带真正的 PT_TLS，musl 能
# dlopen，且外来线程 cgo 不再从 bionic 固定槽读到垃圾 g。
# 真机实测（ALN-AL80/HarmonyOS 6.1）：用原版 Go(GOOS=android) 编的 libsingbox，连最轻量的
# CGoSingBoxVersion 都一调就 SIGSEGV(@0x000103ffd50323b7)，VPN 扩展进程当场死。libxray 现在
# 能用，正是因为它已用本 fork 重编过。
OHOS_GO_FORK="${OHOS_GO_FORK:-${HOME}/hey-ohos-build/ohos_golang_go}"
# build tags（已用真实 sing-box NewService 校验，见 validate_test.go）：
#   with_gvisor / with_utls(reality+uTLS) / with_clash_api(libbox.NewService 必需)。
# ⚠️ 不能加 netgo：openharmony 的 net 端口需要 cgo，加了会报 _C_getifaddrs undefined。
GO_TAGS="${GO_TAGS:-with_gvisor with_utls with_clash_api}"
if [[ -x "${OHOS_GO_FORK}/bin/go" ]]; then
  export PATH="${OHOS_GO_FORK}/bin:${PATH}"
  export GOTOOLCHAIN=local
else
  echo "ERROR: 找不到 OHOS Go fork: ${OHOS_GO_FORK}/bin/go" >&2
  echo "  按 docs/harmonyos-go-tls-wall.md §9.4 构建该工具链:" >&2
  echo "  git clone --branch release-branch.go1.24 https://gitcode.com/openharmony-sig/ohos_golang_go.git" >&2
  echo "  cd ohos_golang_go/src && GOROOT_BOOTSTRAP=/usr/local/go GOTOOLCHAIN=local ./make.bash" >&2
  exit 1
fi

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

cat > "${EXPORTS_FILE}" <<'MAP'
{
  global:
    CGoStartSingBox;
    CGoStopSingBox;
    CGoSetTunFd;
    CGoSingBoxVersion;
  local: *;
};
MAP

# 去掉其余 IE-TLS 重定位，配合 fork 的 tls_g TLSDESC——musl 在 dlopen 的库里只接受
# 通用动态 TLS（global-dynamic / TLSDESC），不接受 initial-exec。
export CGO_CFLAGS="${CGO_CFLAGS:-} -ftls-model=global-dynamic"

cd "${SRC_DIR}"

# [SING-BOX] 拉齐 sing-box / sing-tun / gvisor fork 等依赖。
go mod tidy

# [SING-BOX] gvisor 的 Fstat patch（尽力而为）。
# 背景见 build_libxray_ohos.sh:151-194：gvisor 的 fdbased 端点用 unix.Fstat 判断
# dispatcher，而 HarmonyOS 的 VPN fd 会拒 Fstat。sing-box 走的是 sagernet 的 gvisor
# fork，且 tun 栈在 sing-tun 内自实现，未必命中同一处 isSocketFD。
# 因此这里不中即告警、不中断 —— 真正是否需要 patch、patch 在哪，留待设备上确认。
GVISOR_MODULE_PATH="github.com/sagernet/gvisor"
# 撤掉上一次残留的 replace —— 本 wrapper 是提交进仓库的第一方代码，机器绝对路径的
# replace 绝不能留在 go.mod 里，否则别的机器一构建就炸。reset 后检测看到的是真实上游。
go mod edit -dropreplace="${GVISOR_MODULE_PATH}" 2>/dev/null || true
go mod tidy
if GVISOR_MODULE_VERSION="$(go list -m -f '{{.Version}}' "${GVISOR_MODULE_PATH}" 2>/dev/null)" && [[ -n "${GVISOR_MODULE_VERSION}" ]]; then
  GVISOR_MODULE_DIR="$(go env GOMODCACHE)/${GVISOR_MODULE_PATH}@${GVISOR_MODULE_VERSION}"
  FDBASED_GO="${GVISOR_MODULE_DIR}/pkg/tcpip/link/fdbased/endpoint.go"
  echo "[SING-BOX] gvisor 模块: ${GVISOR_MODULE_PATH}@${GVISOR_MODULE_VERSION}"
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
    print("WARN: isSocketFD 实现与预期不符，跳过 patch（设备上若 Fstat 报错再手动适配）", file=sys.stderr)
else:
    path.write_text(text.replace(old, new))
    print("[SING-BOX] 已 patch gvisor isSocketFD")
PY
    go mod edit -replace="${GVISOR_MODULE_PATH}=${PATCHED_GVISOR_DIR}"
    go mod tidy
  else
    echo "[SING-BOX] WARN: 未在 ${GVISOR_MODULE_PATH} 找到 fdbased/isSocketFD；"
    echo "           sing-tun 可能用自实现的 gvisor 端点。若设备上 tun 因 Fstat 报错，"
    echo "           需到 sing-tun 的 gvisor 栈里找等价处理。" >&2
  fi
else
  echo "[SING-BOX] WARN: 依赖里没找到 gvisor 模块（可能 with_gvisor 没生效）。" >&2
fi

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
  -o "${OUT_DIR}/libsingbox.so" \
  .

# 撤掉构建期注入的 gvisor replace，保持提交进仓库的 go.mod 干净（不含机器绝对路径）。
go mod edit -dropreplace="github.com/sagernet/gvisor"
go mod tidy

echo "Built ${OUT_DIR}/libsingbox.so"
echo "下一步：把 libsingbox.so 加进 CMakeLists 的 PREBUILT_LIB 列表，"
echo "       dlopen 它并先验证 Stage A（CGoSingBoxVersion）。详见 libsingbox/README.md"
