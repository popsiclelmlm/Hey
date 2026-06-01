#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-${SDK_HOME}/default/openharmony/native}"
CC_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
WORK_DIR="${ROOT_DIR}/build/native/libxray-ohos"
SRC_DIR="${WORK_DIR}/src"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"
LIBXRAY_REPO="${LIBXRAY_REPO:-https://github.com/XTLS/libXray.git}"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"
rm -rf "${SRC_DIR}"

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

CGO_ENABLED=1 \
GOOS=linux \
GOARCH=arm64 \
CC="${CC_BIN}" \
CXX="${CXX_BIN}" \
go build \
  -trimpath \
  -ldflags="-s -w" \
  -buildmode=c-shared \
  -o "${OUT_DIR}/libxray.so" \
  .

echo "Built ${OUT_DIR}/libxray.so"
