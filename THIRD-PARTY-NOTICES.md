# Third-Party Notices

Hey VPN is licensed under **GPL-3.0** (see [`LICENSE`](LICENSE)). It bundles and
builds upon the following third-party components, which remain under their own
licenses. Their license terms govern those components even when redistributed as
part of Hey VPN.

## Bundled in the shipped app

### Xray-core — MPL-2.0

- Source: https://github.com/XTLS/Xray-core
- License: Mozilla Public License 2.0 (MPL-2.0)
- Usage: statically linked into the packaged native library
  `entry/src/main/cpp/prebuilt/arm64-v8a/libxray.so`, which is distributed
  inside the HAP.
- Obligation: the corresponding source of the MPL-covered files is available at
  the upstream repository above. The native library is reproduced from source by
  [`scripts/build_libxray_ohos.sh`](scripts/build_libxray_ohos.sh). For an
  exact correspondence between a released `libxray.so` and its source, pin the
  upstream commit/tag in that script (currently it clones the latest `HEAD`).

## Build-time / wrapper

### libXray — MIT

- Source: https://github.com/XTLS/libXray
- License: MIT
- Usage: cloned and lightly modified by
  [`scripts/build_libxray_ohos.sh`](scripts/build_libxray_ohos.sh) to export the
  CGo entry points (`CGoRunXrayFromJSON`, `CGoStopXray`, `CGoPing`,
  `CGoSetTunFd`) and compiled into `libxray.so`.

---

MPL-2.0 is file-level (weak) copyleft and is compatible with GPL-3.0; the
combined work is distributed under GPL-3.0 while the Xray-core files retain
MPL-2.0. MIT is a permissive license and only requires attribution, provided
above.
