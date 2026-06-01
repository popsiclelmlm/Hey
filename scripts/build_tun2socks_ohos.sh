#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
OHOS_NATIVE_HOME="${OHOS_NATIVE_HOME:-${SDK_HOME}/default/openharmony/native}"
CC_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX_BIN="${OHOS_NATIVE_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
ADAPTER_DIR="${ROOT_DIR}/entry/src/main/cpp/tun2socks_adapter"
OUT_DIR="${ROOT_DIR}/entry/src/main/cpp/prebuilt/arm64-v8a"

mkdir -p "${OUT_DIR}"

cd "${ADAPTER_DIR}"
CGO_ENABLED=1 \
GOOS=linux \
GOARCH=arm64 \
CC="${CC_BIN}" \
CXX="${CXX_BIN}" \
go build \
  -trimpath \
  -ldflags="-s -w" \
  -buildmode=c-shared \
  -o "${OUT_DIR}/libheytun2socks.so" \
  .

echo "Built ${OUT_DIR}/libheytun2socks.so"
