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
AR_BIN="${OHOS_NATIVE_HOME}/llvm/bin/llvm-ar"
WORK_DIR="${ROOT_DIR}/build/native/libsingbox-ohos"
# [SING-BOX] 源码是仓库内第一方 wrapper，不 clone。
SRC_DIR="${ROOT_DIR}/libsingbox"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"
EXPORTS_FILE="${WORK_DIR}/libsingbox.exports"
GO_LDFLAGS_DEFAULT="-s -w -checklinkname=0 -linkmode external -extldflags \"-Wl,--version-script=${EXPORTS_FILE} -Wl,-z,lazy\""

# GOOS 选择见 build_libxray_ohos.sh 顶部那段长注释——同一堵 Go-on-musl TLS 墙。
# android：dlopen 可用、VPN 线程可跑，但 UI 线程冷调会 SIGSEGV。先用 android。
GOOS_TARGET="${GOOS_TARGET:-android}"
# [SING-BOX] build tags（缺一不可，已用真实 sing-box NewService 校验，见 validate_test.go）：
#   with_gvisor     tun 的 gvisor 协议栈
#   with_utls       reality 客户端 + uTLS 指纹（生成器会产出 utls/reality，缺则被拒）
#   with_clash_api  libbox.NewService 依赖它创建 command server，缺则核心根本起不来
# netgo 沿用 libxray 的做法。后续加 hysteria2/tuic 等需再补 with_quic。
GO_TAGS="${GO_TAGS:-with_gvisor with_utls with_clash_api netgo}"
ANDROID_STUB_DIR="${WORK_DIR}/android-stub"

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

if [[ "${GOOS_TARGET}" == "android" ]]; then
  mkdir -p "${ANDROID_STUB_DIR}/android"
  cat > "${ANDROID_STUB_DIR}/android/log.h" <<'H'
#pragma once
#include <stdarg.h>
#define ANDROID_LOG_FATAL 6
#ifdef __cplusplus
extern "C" {
#endif
int __android_log_vprint(int prio, const char* tag, const char* fmt, va_list ap);
#ifdef __cplusplus
}
#endif
H
  cat > "${ANDROID_STUB_DIR}/android/api-level.h" <<'H'
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int android_get_device_api_level(void);
#ifdef __cplusplus
}
#endif
H
  cat > "${ANDROID_STUB_DIR}/android_log_stub.c" <<'C'
#include <stdarg.h>
#include <stdio.h>
int __android_log_vprint(int prio, const char* tag, const char* fmt, va_list ap) {
    (void)prio;
    if (tag != 0) {
        fprintf(stderr, "%s: ", tag);
    }
    int n = vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    return n;
}
int android_get_device_api_level(void) {
    return 35;
}
C
  "${CC_BIN}" -c "${ANDROID_STUB_DIR}/android_log_stub.c" -o "${ANDROID_STUB_DIR}/android_log_stub.o"
  "${AR_BIN}" rcs "${ANDROID_STUB_DIR}/liblog.a" "${ANDROID_STUB_DIR}/android_log_stub.o"
  export CGO_CFLAGS="${CGO_CFLAGS:-} -I${ANDROID_STUB_DIR}"
  export CGO_LDFLAGS="${CGO_LDFLAGS:-} -L${ANDROID_STUB_DIR}"
fi

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
GOOS="${GOOS_TARGET}" \
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
