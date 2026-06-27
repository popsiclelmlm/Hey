#!/usr/bin/env bash
set -euo pipefail

# 交叉编译 tun2socks 适配层为 HarmonyOS 的 libheytun2socks.so。
#
# 走 **OHOS 官方 Go fork + GOOS=openharmony**（与 build_libxray/libsingbox 同一套配方），
# 这是目前真机上唯一不崩的编法，详见 docs/building-native-cores.md。
#
# 这是 VPN 数据面的命脉：读 Harmony VPN 的 TUN fd → 转发进内核的本地 SOCKS 入站
# （127.0.0.1:VPN_DATA_SOCKS_PORT）。两个内核（Xray/sing-box）都依赖它，没有它 VPN
# 连上也不过流量。详见 docs/harmonyos-go-tls-wall.md 路径 A。
#
# 源码是仓库内第一方 adapter（entry/src/main/cpp/tun2socks_adapter/，基于
# xjasonlyu/tun2socks v2.6.0 + gvisor netstack）。与旧脚本（提交 5a21b4e 删除前）的区别：
#   旧版用 GOOS=linux + 标准 go + 无 gvisor 补丁（那是 fork 突破之前的写法）；
#   现改为 fork/openharmony，并加 gvisor isSocketFD 补丁（见下）。
#
# ⚠️ 无 OHOS NDK / fork 工具链时无法本机验证编译；改动后请在装好 fork 的环境实跑，
#    并比对产物：nm -D 应见 4 个 HeyTun2Socks* 符号、strings 应含 GOOS=openharmony。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-${SDK_HOME}/default/openharmony/native}"
CC_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
ADAPTER_DIR="${ROOT_DIR}/entry/src/main/cpp/tun2socks_adapter"
WORK_DIR="${ROOT_DIR}/build/native/libheytun2socks-ohos"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"
GO_LDFLAGS_DEFAULT="-s -w -checklinkname=0"

# fork 工具链。
OHOS_GO_FORK="${OHOS_GO_FORK:-${HOME}/hey-ohos-build/ohos_golang_go}"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

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

cd "${ADAPTER_DIR}"

# 拉齐依赖（go.mod/go.sum 已钉死 tun2socks v2.6.0 + gvisor v0.0.0-20250523182742）。
go mod download

# ── gvisor fdbased Fstat 补丁（tun2socks 必需）──────────────────────────────────────
# gvisor 的 fdbased 端点用 unix.Fstat 判断 dispatcher，而 HarmonyOS 的 VPN fd 会拒 Fstat
# （readv/writev 正常）。tun2socks 的 engine 必然把 TUN fd 交给 fdbased，命中此处——不打
# 补丁，engine.Start() 会因 Fstat 失败而 log.Fatal 退出整个进程。故这里是 required：
# 找不到模块或匹配不上就报错退出（而非像 libxray 的 SOCKS 版那样尽力而为）。
GVISOR_MODULE_VERSION="$(go list -m -f '{{.Version}}' gvisor.dev/gvisor 2>/dev/null || true)"
if [[ -z "${GVISOR_MODULE_VERSION}" ]]; then
  echo "ERROR: 依赖里未发现 gvisor.dev/gvisor —— tun2socks 必依赖它，请检查 go.mod。" >&2
  exit 1
fi
GVISOR_MODULE_DIR="$(go env GOMODCACHE)/gvisor.dev/gvisor@${GVISOR_MODULE_VERSION}"
if [[ ! -d "${GVISOR_MODULE_DIR}" ]]; then
  go mod download gvisor.dev/gvisor
fi
FDBASED_GO="${GVISOR_MODULE_DIR}/pkg/tcpip/link/fdbased/endpoint.go"
if [[ ! -f "${FDBASED_GO}" ]] || ! grep -q 'func isSocketFD(fd int)' "${FDBASED_GO}"; then
  echo "ERROR: 未在 gvisor@${GVISOR_MODULE_VERSION} 找到 fdbased/isSocketFD；" >&2
  echo "       gvisor 版本可能变了，需人工适配补丁位置。" >&2
  exit 1
fi
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
    raise SystemExit("ERROR: isSocketFD 实现与预期不符，需人工适配 gvisor 补丁。")
path.write_text(text.replace(old, new))
print("Patched gvisor isSocketFD")
PY
go mod edit -replace="gvisor.dev/gvisor=${PATCHED_GVISOR_DIR}"

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
  -o "${OUT_DIR}/libheytun2socks.so" \
  .

# 撤掉构建期注入的 gvisor replace，保持提交进仓库的 go.mod 干净（不含机器绝对路径）。
go mod edit -dropreplace="gvisor.dev/gvisor"

echo "Built ${OUT_DIR}/libheytun2socks.so (GOOS=openharmony)"
