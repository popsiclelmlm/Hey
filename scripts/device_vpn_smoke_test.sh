#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
HVIGOR="${HVIGOR:-/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw}"
HDC="${HDC:-${DEVECO_SDK_HOME}/default/openharmony/toolchains/hdc}"
HAP="${ROOT_DIR}/entry/build/default/outputs/default/app/entry-default.hap"

usage() {
  printf 'Usage: %s {build|install|logs|targets}\n' "$0"
}

require_hdc() {
  if [[ ! -x "${HDC}" ]]; then
    printf 'hdc not found: %s\n' "${HDC}" >&2
    exit 1
  fi
}

case "${1:-}" in
  build)
    DEVECO_SDK_HOME="${DEVECO_SDK_HOME}" "${HVIGOR}" assembleApp --no-daemon --stacktrace
    unzip -l "${HAP}" | awk '/lib(heyvpn|xray|heytun2socks)\.so/ { print }'
    ;;
  install)
    require_hdc
    if [[ ! -f "${HAP}" ]]; then
      printf 'HAP not found, run build first: %s\n' "${HAP}" >&2
      exit 1
    fi
    "${HDC}" install -r "${HAP}"
    ;;
  logs)
    require_hdc
    "${HDC}" shell hilog | awk '/HeyVpnAbility|HeyNative/ { print; fflush(); }'
    ;;
  targets)
    require_hdc
    "${HDC}" list targets
    ;;
  *)
    usage
    exit 1
    ;;
esac
