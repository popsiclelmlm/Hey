# v2rayNG Feature Parity Map

This project targets feature parity with the Android reference v2rayNG
(<https://github.com/2dust/v2rayNG>) without copying Android/Kotlin source,
XML layouts, drawable assets, launcher artwork, strings, or package branding.

Status below is maintained against the actual code; routing, subscription, and
custom config import status were refreshed on 2026-06-18. For the phased
delivery plan, see
[`development-plan.md`](development-plan.md). For an in-depth analysis of
v2rayNG's features and design, see
[`v2rayng-analysis/`](v2rayng-analysis/README.md).

## Page Map

| Android reference area | Harmony page | Current status |
| --- | --- | --- |
| MainActivity / MainRecyclerAdapter | Nodes | Present. Lists subscription nodes, search, select current node, start/stop/restart VPN. |
| Add config menu | Add | Present. Imports share links, outbound JSON, or subscription URL; protocol tabs are scaffolded. |
| ScannerActivity / ScScannerActivity | Scan | Present. Paste/import path and camera QR capture via ScanKit are wired. |
| SubSettingActivity / SubEditActivity | Subs | Multi-group model present. Save/update/update-all/select/enable-disable/delete/reorder are wired; dedicated edit form supports name, URL, User-Agent, node-name filter, subscription-level insecure URL opt-in, auto-update opt-in, and update interval. Foreground due refresh is wired; true background scheduling remains pending. |
| ServerActivity protocol editors | Add | Partial. Field-level editor is present for VLESS/VMess/Trojan/Shadowsocks/SOCKS/HTTP (generates outbound JSON into import buffer). WireGuard/Hysteria2/TUIC editors still pending. |
| ServerCustomConfigActivity | Add | Present for pasted/file JSON. Raw outbound JSON and full Xray config import work; full configs persist as custom manual nodes and start without Hey wrapping them in generated TUN/routing config. Advanced custom-config editing remains pending. |
| RoutingSettingActivity / RoutingEditActivity | Route | Present for core ruleset management. Traffic mode (global/rules/direct), domain strategy, bypass-LAN/CN, ad-block, custom routing rules, locked rules, predefined ruleset import, clipboard import, and clipboard export persist and feed generated Xray routing. Advanced custom outbound targets remain future work. |
| SettingsActivity | Config | Core, VPN DNS, local HTTP proxy append, mux, sniffing, log level and routing strategy persist; VPN DNS feeds Harmony `VpnConfig.dnsAddresses`, while remote/domestic DNS feed generated Xray DNS. Dedicated pickers and full advanced options pending. |
| PerAppProxyActivity | Apps | Partial. Toggle, allowlist/blocklist mode, preset/manual package list, and VPN `blockedApplications`/`trustedApplications` mapping are wired; unrestricted installed-app enumeration is platform-limited. |
| UserAssetActivity / UserAssetUrlActivity | Assets | Present. geoip/geosite download (Loyalsoldier rules), custom asset URL CRUD, and clipboard backup/restore are implemented. |
| LogcatActivity | Logs | Present. App diagnostic logs and native runtime stats are visible. |
| AboutActivity | About | Present. Harmony-specific about/license note. |
| TaskerActivity / shortcuts / widgets / QS tile | Platform equivalents | Pending. Android-only entry points need Harmony shortcuts/widgets equivalents. |
| UrlSchemeActivity | Import entry | Present. Harmony Want/deep-link import handles subscription and config links. |

## Business Function Map

| Function | Current status |
| --- | --- |
| Subscription URL fetch and parse | Present for `vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`, `http://`, `https://`, `wireguard://`, `hysteria2://`, `hy2://`. |
| Node select and save current profile | Present. |
| Xray config generation | Present for outbound + native TUN inbound + metrics inbound + optional local HTTP proxy inbound + basic direct/block outbounds. Full custom Xray configs are validated and passed through unchanged at runtime. |
| Persistent app settings | Present for core VPN, DNS, mux, sniffing, log and routing strategy; selected values are applied at connection start, including VPN interface DNS. |
| VPN Extension start/stop | Present, with emulator timeout diagnostics. Real-device verified (2026-06-15). |
| Xray native TUN runtime | Present in HAP via `CGoSetTunFd` + Xray TUN inbound. Real-device closed loop verified (2026-06-15): TUN → Xray → outbound → reachable. |
| VMess/VLESS/Trojan/Shadowsocks parsing | Present. |
| SOCKS/HTTP/WireGuard/Hysteria2 parsing | Present for share-link import and subscription discovery; WireGuard `[Interface]/[Peer]` `.conf` text/file import is also supported. Runtime connection for WireGuard/Hysteria2 still needs core validation. |
| TUIC parsing | Pending. |
| Delay test / real ping / sort by delay | Present. Per-node real outbound delay via libXray `CGoPing` (own SOCKS test inbound on port 10825), persisted per node, with sort-by-delay. Falls back to direct URL test when the native core is unavailable (e.g. emulator). Needs real-device validation. |
| Delete all / duplicate / invalid configs | Present for the active subscription group. Delete-all, duplicate cleanup, and invalid-node cleanup are wired from the Nodes menu. |
| Export/share configs and QR generation | Present for text-oriented flows. Plain-text share-link/exported JSON output is present, full custom configs export as JSON text, node detail can render QR codes for share-link nodes, Export can save the current group to a `.txt` file, and batch/single-node text can be sent through the Harmony system share sheet with clipboard fallback. |
| Multi-subscription groups | Present with legacy single-subscription migration. Rename/edit, enable-disable, delete, reorder, batch update all, per-subscription insecure URL opt-in, auto-update opt-in, and update interval are wired. Foreground due refresh is wired, and subscription fetches can prefer the local HTTP proxy when the VPN runtime exposes it. Background refresh remains pending. |
| Routing rulesets and geo assets | Partial. Geo asset download/management present (Assets page). Routing config emits metrics, ad-block, custom enabled rules, and bypass-LAN/CN rules in order. Predefined ruleset import/export is wired; advanced outbound targets are still pending. |
| Per-app proxy | Partial. VPN app allow/block mapping is wired from saved package names; unrestricted installed-app enumeration remains platform-limited. |
| Auto subscription update | Partial. Per-subscription `autoUpdate` and `updateIntervalMinutes` persist with v2rayNG-compatible defaults (1440 minutes, minimum 15), and the home page performs throttled foreground due refresh through the local HTTP proxy when available. Harmony background scheduling remains pending. |
| Boot/startup automation | Pending and platform-dependent. |

## Native Bridge Status

`libxray.so` exports 13 CGo functions; `napi_init.cpp` wires 7 (M1, 2026-06-15).

- Wired (runtime): `CGoRunXrayFromJSON`, `CGoStopXray`, `CGoPing`, `CGoSetTunFd`.
- Wired (M1): `CGoQueryStats` (real per-tag traffic via the Xray metrics
  `/debug/vars` endpoint), `CGoTestXray` (pre-connect config preflight),
  `CGoXrayVersion` (core version on the About page).
- Idle: `CGoReadGeoFiles` / `CGoCountGeoData` (geo validation),
  `CGoConvertShareLinksToXrayJson`, `CGOConvertXrayJsonToShareLinks`,
  `CGoGetFreePorts`, `CGoRunXray`.

> M1 note: the prebuilt `libxray.so` version script previously exported only the
> 4 runtime symbols (`local: *` hid the rest). `scripts/build_libxray_ohos.sh`
> now also exports `CGoQueryStats`/`CGoTestXray`/`CGoXrayVersion`, so the bridge
> code is complete but a **`libxray.so` rebuild + device retest** is required
> before these three take effect. Until then the bridge degrades gracefully
> (stats fall back, preflight is skipped, version shows the static label).
