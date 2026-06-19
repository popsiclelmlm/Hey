#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-${SDK_HOME}/default/openharmony/native}"
CC_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
AR_BIN="${OHOS_NATIVE_HOME}/llvm/bin/llvm-ar"
WORK_DIR="${ROOT_DIR}/build/native/libxray-ohos"
SRC_DIR="${WORK_DIR}/src"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"
LIBXRAY_REPO="${LIBXRAY_REPO:-https://github.com/XTLS/libXray.git}"
EXPORTS_FILE="${WORK_DIR}/libxray.exports"
GO_LDFLAGS_DEFAULT="-s -w -checklinkname=0 -linkmode external -extldflags \"-Wl,--version-script=${EXPORTS_FILE} -Wl,-z,lazy\""
GOOS_TARGET="${GOOS_TARGET:-android}"
ANDROID_STUB_DIR="${WORK_DIR}/android-stub"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"
rm -rf "${SRC_DIR}"
cat > "${EXPORTS_FILE}" <<'MAP'
{
  global:
    CGoRunXrayFromJSON;
    CGoStopXray;
    CGoPing;
    CGoSetTunFd;
    CGoQueryStats;
    CGoTestXray;
    CGoXrayVersion;
    CGoCountGeoData;
    CGoReadGeoFiles;
    CGoGetFreePorts;
    CGoConvertShareLinksToXrayJson;
    CGOConvertXrayJsonToShareLinks;
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

if [[ -n "${LIBXRAY_SRC:-}" ]]; then
  cp -R "${LIBXRAY_SRC}" "${SRC_DIR}"
else
  git clone --depth 1 "${LIBXRAY_REPO}" "${SRC_DIR}"
fi

cd "${SRC_DIR}"
cp build/template/main.gotemplate main.go
python3 - <<'PY'
from pathlib import Path

for path in Path(".").glob("*.go"):
    text = path.read_text()
    path.write_text(text.replace("package libXray\n", "package main\n"))
PY

if [[ "${GOOS_TARGET}" == "android" ]]; then
  python3 - <<'PY'
from pathlib import Path

path = Path("main.go")
text = path.read_text()
for block in [
    """//export CGoInitDns
func CGoInitDns(base64Text *C.char) *C.char {
\ttext := C.GoString(base64Text)
\treturn C.CString(InitDns(text))
}

""",
    """//export CGoResetDns
func CGoResetDns() *C.char {
\treturn C.CString(ResetDns())
}

""",
]:
    if block not in text:
        raise SystemExit(f"expected Android-incompatible export block not found: {block.splitlines()[0]}")
    text = text.replace(block, "")
path.write_text(text)
PY
fi

if [[ "${GOOS_TARGET}" == "android" ]]; then
  GVISOR_MODULE_VERSION="$(go list -m -f '{{.Version}}' gvisor.dev/gvisor)"
  GVISOR_MODULE_DIR="$(go env GOMODCACHE)/gvisor.dev/gvisor@${GVISOR_MODULE_VERSION}"
  PATCHED_GVISOR_DIR="${WORK_DIR}/gvisor-patched"

  if [[ ! -d "${GVISOR_MODULE_DIR}" ]]; then
    go mod download gvisor.dev/gvisor
  fi

  if [[ -d "${PATCHED_GVISOR_DIR}" ]]; then
    chmod -R u+w "${PATCHED_GVISOR_DIR}"
  fi
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
\t// HarmonyOS VPN file descriptors can reject Fstat even when readv/writev
\t// works. Xray's Android TUN inbound passes a TUN fd here, so force the
\t// portable non-socket Readv dispatcher and avoid Fstat entirely.
\treturn false, nil
}
"""
if old not in text:
    raise SystemExit("expected fdbased isSocketFD implementation not found")
path.write_text(text.replace(old, new))
PY

  go mod edit -replace="gvisor.dev/gvisor=${PATCHED_GVISOR_DIR}"
fi

CGO_ENABLED=1 \
GOOS="${GOOS_TARGET}" \
GOARCH=arm64 \
CC="${CC_BIN}" \
CXX="${CXX_BIN}" \
go build \
  -tags "${GO_TAGS:-netgo}" \
  -trimpath \
  -ldflags="${GO_LDFLAGS:-${GO_LDFLAGS_DEFAULT}}" \
  -buildmode=c-shared \
  -o "${OUT_DIR}/libxray.so" \
  .

echo "Built ${OUT_DIR}/libxray.so"
