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

### sing-box — GPL-3.0-or-later

- Source: https://github.com/SagerNet/sing-box
- License: GNU General Public License v3.0 or later (GPL-3.0-or-later)
- Usage: wrapped by the repository's `libsingbox/` CGo bridge and distributed
  as `entry/src/main/cpp/prebuilt/arm64-v8a/libsingbox.so`.
- Obligation: the complete corresponding source for Hey VPN is distributed
  under GPL-3.0, and the sing-box source is available from the upstream
  repository above. Released builds should keep `libsingbox/go.mod` pinned to
  the exact sing-box version used for the packaged library.

### tun2socks — MIT

- Source: https://github.com/xjasonlyu/tun2socks
- License: MIT
- Usage: used by the bundled `libheytun2socks.so` adapter (the default "gvisor"
  TUN engine) to relay the HarmonyOS VPN TUN fd into the selected core's local
  SOCKS inbound.

### hev-socks5-tunnel — MIT

- Source: https://github.com/heiher/hev-socks5-tunnel
- License: MIT
- Usage: cross-compiled (with its `hev-task-system` and `yaml` submodules) into
  `entry/src/main/cpp/prebuilt/arm64-v8a/libhevsocks5tun.so` by
  [`scripts/build_hev_ohos.sh`](scripts/build_hev_ohos.sh). It is the optional
  high-performance TUN engine selected by the "Use Hev TUN engine" setting; the
  same TUN-fd → local SOCKS relay as tun2socks, implemented in C.

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
MPL-2.0. sing-box is GPL-3.0-or-later, which is aligned with Hey VPN's GPL-3.0
distribution. MIT is a permissive license and only requires attribution,
provided above.
