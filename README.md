<div align="center">

<img src="design/app-icon/startIcon.png" alt="Hey VPN" width="160" height="160" />

# Hey VPN

**A HarmonyOS VPN client powered by a native Xray core.**

<p>
  <img src="https://img.shields.io/badge/platform-HarmonyOS%20NEXT-0A0A0A" alt="platform" />
  <img src="https://img.shields.io/badge/ArkTS-API%2024-1E88E5" alt="ArkTS API 24" />
  <img src="https://img.shields.io/badge/core-Xray-6E56CF" alt="Xray core" />
  <img src="https://img.shields.io/badge/version-1.2.0-E85D04" alt="version 1.2.0" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-3DA639" alt="license GPL-3.0" /></a>
</p>

English · [简体中文](README.zh-CN.md)

</div>

---

Hey VPN is a HarmonyOS VPN client built with ArkTS, Stage model abilities,
and a native proxy core (Xray, with sing-box as a selectable second core). It
imports proxy nodes and subscriptions, generates a runtime config, starts a
HarmonyOS VPN Extension, and routes the device TUN flow into the core through a
bundled `tun2socks` adapter that feeds a local SOCKS inbound.

The current native data path (same for both cores) is:

```text
User connects
  -> vpnExtension.startVpnExtensionAbility(...)
  -> HeyVpnAbility.onCreate(want)
  -> vpnExtension.createVpnConnection(context)
  -> vpnConnection.create(vpnConfig)
  -> TUN fd
  -> libheyvpn.so dlopen(libxray.so / libsingbox.so)
  -> CGoRunXrayFromJSON(config) / CGoStartSingBox(config)
       (core opens a local SOCKS inbound on 127.0.0.1:10810)
  -> libheyvpn.so dlopen(libheytun2socks.so)
  -> HeyTun2SocksStart(tunFd, 127.0.0.1, 10810, mtu)
       (forwards Harmony TUN fd traffic into the SOCKS inbound)
  -> core SOCKS inbound -> core outbound (proxy node)
```

> Why tun2socks instead of the core's native TUN inbound: the Go-on-HarmonyOS
> (musl) TLS wall and the toolchain gap for the native-TUN entry points pushed
> the data path back to `TUN fd -> tun2socks -> SOCKS inbound`, which works with
> the OHOS Go fork build. See
> [`docs/harmonyos-go-tls-wall.md`](docs/harmonyos-go-tls-wall.md).

## Status

The client is feature-complete across the UI and config layers: node and
subscription management, share-link and JSON import, Xray config generation,
native delay testing, routing, geo-asset management, per-app proxy, and the
full VPN extension startup path are all implemented and wired to the native
bridge. The remaining gap is end-to-end traffic validation, which should be
done on a real HarmonyOS device because some emulator/system images do not
include the VPN authorization component.

## Download

Signed HAP packages are published on the
[**Releases**](https://github.com/popsiclelmlm/Hey/releases) page. Grab the
latest `entry-default-signed.hap` and install it with DevEco Studio or `hdc`
(see [Install And Test](#install-and-test)). Building from source is covered
below.

> Note: the UI and config layers are feature-complete; end-to-end VPN traffic
> should be validated on a real HarmonyOS device (see Status).

## Features

- HarmonyOS Stage app with `EntryAbility` and `HeyVpnAbility`, plus core VPN routing, config, and sharing flows.
- Node list, search, selection, start/stop/restart controls, and runtime status.
- Import of subscription URLs, Xray outbound JSON, and share links, with
  multi-subscription groups and per-node detail/edit pages.
- Share-link parsing for `vless://`, `vmess://`, `trojan://`, `ss://`,
  `socks://`, `http(s)://`, `wireguard://`, and `hysteria2://` / `hy2://`.
- Runtime config generation with a local SOCKS inbound (fed by the tun2socks
  data path) plus proxy/direct/block outbounds, and routing rules (bypass LAN/CN).
- Native N-API bridge for packaged `libxray.so` / `libsingbox.so` /
  `libheytun2socks.so`, including core lifecycle entry points, the tun2socks
  adapter, and real per-node delay testing (`CGoPing`).
- Geo-asset management (geoip/geosite download, custom URLs, and status/count feedback).
- Per-app proxy with allow/deny modes, a preset app list, and manual package
  entry (HarmonyOS NEXT restricts global app enumeration).
- Scan/import and export pages, diagnostic log panel, native runtime stat
  display, settings, and an about page — with full English/Chinese i18n.

## Project Layout

```text
AppScope/                         App-level HarmonyOS metadata and resources
entry/src/main/ets/               ArkTS UI, services, storage, VPN ability
entry/src/main/cpp/               Native N-API bridge and prebuilt core notes
entry/src/main/cpp/prebuilt/      Packaged arm64-v8a native libraries
scripts/                          Native build and device smoke-test scripts
docs/                             Real-device test documentation
```

## Requirements

- DevEco Studio / HarmonyOS SDK 6.1.1, API 24.
- A HarmonyOS phone or tablet for end-to-end VPN testing.
- Go and DevEco native toolchains when rebuilding the Xray shared library.

## Build

Build the app with the project smoke-test script:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk ./scripts/device_vpn_smoke_test.sh build
```

The output HAP is expected at:

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

Rebuild the Xray native core when needed:

```bash
./scripts/build_libxray_ohos.sh
```

The script places `libxray.so` and `libxray.h` under
`entry/src/main/cpp/prebuilt/arm64-v8a/`.

## Install And Test

List connected targets:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk ./scripts/device_vpn_smoke_test.sh targets
```

Install the HAP:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk ./scripts/device_vpn_smoke_test.sh install
```

Watch VPN and native bridge logs:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk ./scripts/device_vpn_smoke_test.sh logs
```

## Native Core

The native bridge builds `libheyvpn.so` and loads packaged Go shared libraries:
the proxy core (`libxray.so`, plus `libsingbox.so` for the optional second core)
and the `tun2socks` adapter (`libheytun2socks.so`). These are documented in
[`entry/src/main/cpp/README.md`](entry/src/main/cpp/README.md).

Hey VPN forwards the VPN data path through `tun2socks`. HarmonyOS creates the
VPN TUN fd; the selected core starts with a local SOCKS inbound on
`127.0.0.1:10810`; `libheyvpn.so` then loads `libheytun2socks.so` and calls
`HeyTun2SocksStart(tunFd, 127.0.0.1, 10810, mtu)` to relay the TUN fd's traffic
into that SOCKS inbound. The core's native TUN inbound (`CGoSetTunFd` /
`protocol: "tun"`) is no longer used on the VPN data path — see
[`docs/harmonyos-go-tls-wall.md`](docs/harmonyos-go-tls-wall.md) for why.

## Roadmap

- Real-device VPN traffic validation across more HarmonyOS versions.
- Node sorting, duplicate cleanup, and automatic subscription refresh.
- Camera-based QR scanning and QR code generation for share/export.
- Protocol editors for advanced VLESS/VMess/Trojan/Shadowsocks/WireGuard/
  Hysteria2 fields, plus TUIC support.
- Expanded routing rulesets, including ad-blocking and custom rule editing.
- HarmonyOS deep-link import, shortcuts, and platform-specific automation.

## License

Copyright (C) 2026 popsiclelmlm

Hey VPN is licensed under the [GNU General Public License v3.0](LICENSE).
You may use, modify, and redistribute it — including commercially — provided
derivative works remain under GPL-3.0 and you make the corresponding source
available.

It bundles the Xray native core (Xray-core, MPL-2.0) and builds on libXray
(MIT). Those components keep their own licenses; see
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for details.
