<div align="center">

<img src="design/app-icon/startIcon.png" alt="Hey VPN" width="160" height="160" />

# Hey VPN

**A HarmonyOS NEXT VPN client built around Xray, with a selectable sing-box preview core.**

<p>
  <img src="https://img.shields.io/badge/platform-HarmonyOS%20NEXT-0A0A0A" alt="platform" />
  <img src="https://img.shields.io/badge/target-6.0.1%20(21)-1E88E5" alt="target SDK 6.0.1(21)" />
  <img src="https://img.shields.io/badge/core-Xray%20%2B%20sing--box-6E56CF" alt="Xray and sing-box cores" />
  <img src="https://img.shields.io/badge/version-1.3.0-E85D04" alt="version 1.3.0" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-3DA639" alt="license GPL-3.0" /></a>
</p>

English · [简体中文](README.zh-CN.md)

</div>

---

Hey VPN is a HarmonyOS NEXT app written in ArkTS. The codebase uses the Stage
model, a VPN Extension Ability, a form-based control card, WorkScheduler,
ScanKit QR scanning, launcher shortcuts, `hey://` deep links, system share
import, and a native N-API bridge for the packaged proxy cores.

The main runtime is Xray. sing-box is also packaged and can be selected in
settings, but its app integration is intentionally narrower today.

## Current State

The Xray path is the production path in this repository. It supports VPN mode
and proxy-only mode, generates runtime Xray config from the selected profile,
starts/stops the HarmonyOS VPN Extension, and routes VPN traffic through the
packaged `libheytun2socks.so` adapter.

The current VPN data path for both cores is:

```text
HarmonyOS VPN TUN fd
  -> libheytun2socks.so
  -> 127.0.0.1:10810 (local SOCKS/mixed inbound)
  -> Xray or sing-box outbound
```

This is why the app does not hand the TUN fd directly to Xray or sing-box. The
OpenHarmony Go fork and TLSDESC build route are documented in
[`docs/harmonyos-go-tls-wall.md`](docs/harmonyos-go-tls-wall.md), and the native
build notes are in [`docs/building-native-cores.md`](docs/building-native-cores.md).

The sing-box path currently supports VPN mode with one converted outbound.
The converter accepts VLESS, VMess, Trojan, Shadowsocks, AnyTLS, and TUIC, with
basic tcp/ws/grpc/http/httpupgrade transport mapping and none/tls/reality
security mapping. It does not yet support full configs, proxy chains, policy
groups, proxy-only mode, Hysteria2, WireGuard, SOCKS, HTTP, or sing-box-native
traffic stats.

## Implemented In Code

- HarmonyOS entry points: `EntryAbility`, `HeyVpnAbility`, `ControlCardAbility`,
  `SubscriptionUpdateWorkAbility`, launcher shortcuts, `hey://` routes, and
  `text/plain` system share import.
- Pages for server list, node detail/edit, import, JSON import, advanced
  outbound, subscriptions, subscription detail/edit, routing, settings,
  language, per-app proxy, assets, logs, scanner, backup, export, and about.
- Node and subscription handling: multiple subscription groups, selected group
  and node state, custom User-Agent, filters, pre/post profile fields, manual
  refresh, due refresh, WorkScheduler background refresh, search/sort/cleanup,
  and real delay testing through the native bridge.
- Imports: subscription URLs, v2rayN plain/base64 text, Xray outbound/full JSON,
  Clash-style YAML proxy entries, WireGuard config files, QR codes, system share
  text, and share links for `vless://`, `vmess://`, `trojan://`, `ss://`,
  `socks://`, `socks4://`, `socks5://`, `http://`, `https://`,
  `wireguard://`, `hysteria2://`, `hy2://`, `anytls://`, and `tuic://`.
- Exports: node share links for the protocols implemented by
  `formatOutboundJsonToShareLink`, QR generation on export/detail flows, routing
  rule JSON, and full local backup JSON.
- Xray runtime config: VPN SOCKS inbound for `tun2socks`, optional local
  SOCKS/HTTP proxy, proxy/direct/block outbounds, DNS settings, sniffing,
  mux, fragmentation/finalmask, Hysteria2 runtime shape, WireGuard IPv6
  handling, proxy chains, policy groups, metrics, and routing rules.
- Routing: traffic modes, domain strategy, LAN/CN/global/Iran/Russia/ad-block
  presets, custom rules, locked rules, process/port/network/protocol matchers,
  and rule import/export.
- Per-app proxy: allow/bypass mode plus stored package-name list. HarmonyOS NEXT
  does not expose a general global app enumeration path here, so manual or
  preset package entries remain part of the design.
- Assets and diagnostics: built-in geo source definitions, custom geo asset
  URLs, native geo data counting, runtime logs, core logs, optional speed
  display, persistent traffic totals, update checking, remote IP info, and
  English/Chinese plus additional language resources.
- Backup/restore: profile, subscription groups, settings, routing rules,
  per-app list, and custom asset URLs are exported as local JSON. Runtime
  traffic totals and control-card state are intentionally not migrated.

## Known Limits

- End-to-end VPN behavior still needs real-device coverage across more
  HarmonyOS NEXT devices and system versions. Some emulator/system images lack
  the VPN authorization component.
- sing-box is a preview runtime in the app: it is packaged and selectable, but
  the app only starts it for VPN mode with a single supported outbound.

## Project Layout

```text
AppScope/                         App metadata, version, icon, label
entry/src/main/ets/               ArkTS UI, stores, services, routing, VPN code
entry/src/main/cpp/               N-API bridge and native library packaging
entry/src/main/cpp/prebuilt/      Packaged arm64-v8a .so files
libsingbox/                       Go wrapper for the sing-box c-shared library
scripts/                          App build/install/log scripts and native builds
docs/                             Native build and HarmonyOS notes
```

## Build And Install

The app is configured for HarmonyOS target SDK `6.0.1(21)` and compatible SDK
`5.1.1(19)`. The project smoke-test script wraps `hvigorw` and `hdc`.

Build the signed HAP:

```bash
./scripts/device_vpn_smoke_test.sh build
```

If DevEco Studio is not in the default macOS location, pass the SDK/tool paths:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
HVIGOR=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
./scripts/device_vpn_smoke_test.sh build
```

The expected output is:

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

Useful device commands:

```bash
./scripts/device_vpn_smoke_test.sh targets
./scripts/device_vpn_smoke_test.sh doctor
./scripts/device_vpn_smoke_test.sh install
./scripts/device_vpn_smoke_test.sh logs
```

## Native Libraries

`libheyvpn.so` is built from `entry/src/main/cpp/napi_init.cpp`. CMake then
copies the packaged Go shared libraries into the HAP native library directory:

| Library | Current role | Build status |
| --- | --- | --- |
| `libxray.so` | Main Xray runtime; exports start/stop, ping, and stats entry points. | Scripted by `scripts/build_libxray_ohos.sh`. |
| `libsingbox.so` | Optional sing-box runtime; exports start/stop/version/probe entry points. | Scripted by `scripts/build_libsingbox_ohos.sh`. |
| `libheytun2socks.so` | Relays the HarmonyOS VPN TUN fd into the core's local inbound. | Packaged and used; built by `scripts/build_tun2socks_ohos.sh`. |

Both scripted Go builds use the OpenHarmony Go fork with `GOOS=openharmony`.
Keep the fork toolchain outside the repository; `hvigor clean` removes the
repository `build/` directory.

## License

Copyright (C) 2026 popsiclelmlm

Hey VPN is released under the [GNU General Public License v3.0](LICENSE). You
may use, modify, and redistribute it, including commercially, as long as
derivative works stay under GPL-3.0 and the corresponding source is made
available.

The project packages Xray-core (MPL-2.0), builds on libXray (MIT), packages
sing-box (GPL-3.0-or-later), and uses a tun2socks adapter based on
xjasonlyu/tun2socks (MIT). These components keep their own licenses; see
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
