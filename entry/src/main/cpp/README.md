# Hey Native Core

English · [简体中文](README.zh-CN.md)

`libheyvpn.so` is the ArkTS N-API bridge. It `dlopen`s the packaged Go shared
libraries beside it:

- `libxray.so` — the Xray proxy core (built from XTLS/libXray `v26.7.28`,
  `cgo_bridge/`). Exports only two symbols:
  - `CGoInvoke(char* requestJSON) -> char*` — the single dispatch entry. The
    bridge sends `{"apiVersion":1,"method":"...","payload":{...}}` and gets back
    raw (not base64) JSON `{success, data, error}`. It currently uses
    `runXrayFromJson` (the VPN config opens a local SOCKS inbound on
    `127.0.0.1:18082`), `stopXray`, and `ping` (per-node outbound delay).
  - `CGoFree(char* value)` — frees a string returned by `CGoInvoke`; never use
    `free()` on it.

  Older optional symbols (`CGoQueryStats`, `CGoCountGeoData`, ...) are no longer
  exported; the bridge sees null from `dlsym` and degrades gracefully.
- `libsingbox.so` — the optional second core (sing-box). Exports
  `CGoStartSingBox` / `CGoStopSingBox` (plus a UI-safe probe). Like Xray, its VPN
  config opens a local SOCKS inbound rather than a native TUN inbound.
- `libheytun2socks.so` — the `tun2socks` adapter. Exports
  `HeyTun2SocksStart(fd, host, port, mtu)` / `HeyTun2SocksStop()` and byte
  counters. It relays the Harmony VPN TUN fd's traffic into the core's local
  SOCKS inbound.

## Data path

```text
TUN fd  ->  libheytun2socks.so  ->  127.0.0.1:18082 (core SOCKS inbound)  ->  outbound
```

The core's native TUN inbound (`CGoSetTunFd` / `protocol: "tun"`) is **not** used
on the VPN data path. The Go-on-HarmonyOS (musl) TLS wall and the toolchain gap
for the native-TUN entry points pushed the data path back to
`TUN fd -> tun2socks -> SOCKS inbound`. See
[`docs/harmonyos-go-tls-wall.md`](../../../../docs/harmonyos-go-tls-wall.md).

## Build

The shipped `libxray.so` / `libsingbox.so` / `libheytun2socks.so` are built with
an **OpenHarmony-port Go toolchain** (star4277/ohos-go `v1.26.5-beta1`, go1.26.5,
`GOOS=openharmony`, arm64 **TLSDESC**) so that cgo works from ArkTS/foreign
threads and the libraries `dlopen` cleanly on musl.
The native-TUN entry points are leftovers from an earlier experiment: `libxray.so`
drops `CGoSetTunFd` entirely, while `libsingbox.so` still ships it (and its
`OpenTun()` stub) but nothing on the SOCKS data path ever calls it.

`scripts/build_libxray_ohos.sh` and `scripts/build_libsingbox_ohos.sh` default
to the `openharmony` fork build. The authoritative build recipe (toolchain
setup, pinned revisions, per-library exports, and artifact checks) lives in
[`docs/building-native-cores.md`](../../../../docs/building-native-cores.md);
the underlying TLS rationale is in
[`docs/harmonyos-go-tls-wall.md`](../../../../docs/harmonyos-go-tls-wall.md).
CMake copies the prebuilt `.so` files from
`entry/src/main/cpp/prebuilt/arm64-v8a/` into the HAP native library directory
after building `libheyvpn.so`.

## Environment variables and `dlopen`

`PrepareXrayAssetDir` in `napi_init.cpp` sets `XRAY_LOCATION_ASSET` (the Geo data
directory; libXray `v26.7.28` no longer takes `datDir` in run/ping requests)
**before** the first `dlopen` of `libxray.so`. Never call `setenv` after any Go
c-shared library is loaded: Go copies `environ` only once during runtime init,
and that init runs asynchronously on another thread after `dlopen` returns, so a
later C `setenv` (musl reallocs/frees the `environ` array) races with it and
crashed the VPN extension process with SIGSEGV. Details are in
[`docs/building-native-cores.md`](../../../../docs/building-native-cores.md) §5.
