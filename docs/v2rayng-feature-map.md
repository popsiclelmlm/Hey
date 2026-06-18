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
| Add config menu | Add | Present. Imports share links, outbound JSON, proxy-chain JSON, policy-group JSON, or subscription URL; proxy-chain/policy-group configs can also be built from existing ordinary outbound nodes through the advanced outbound member selector. Policy groups can use static selected members or v2rayNG-style dynamic members from a subscription group plus node-name regex filter. Protocol tabs are scaffolded. |
| ScannerActivity / ScScannerActivity | Scan | Present. Paste/import path and camera QR capture via ScanKit are wired. |
| SubSettingActivity / SubEditActivity | Subs | Multi-group model present. Save/update/update-all/select/enable-disable/delete/reorder are wired; dedicated edit form supports name, URL, User-Agent, node-name filter, subscription-level insecure URL opt-in, auto-update opt-in, and update interval. Foreground due refresh is wired; true background scheduling remains pending. |
| ServerActivity protocol editors | Add | Partial. Field-level editor is present for VLESS/VMess/Trojan/Shadowsocks/SOCKS/HTTP/WireGuard/Hysteria2 and saves validated outbound JSON. TUIC editor remains pending. |
| ServerCustomConfigActivity | Add | Present for pasted/file JSON. Raw outbound JSON and full Xray config import work; full configs persist as custom manual nodes and start without Hey wrapping them in generated TUN/routing config. Manual full custom config nodes can be reopened from node detail, edited with a name plus JSON content, revalidated, and saved back to the same node/profile when selected. |
| RoutingSettingActivity / RoutingEditActivity | Route | Present for core ruleset management. Traffic mode (global/rules/direct), domain strategy, bypass-LAN/CN, ad-block, custom routing rules, locked rules, predefined ruleset import, clipboard import, and clipboard export persist and feed generated Xray routing. Proxy-chain and policy-group runtime generation are available through JSON-imported or UI-built advanced nodes; routing-rule target selection can use the current advanced outbound. |
| SettingsActivity | Config | Core, VPN DNS, IPv6 preference, local HTTP proxy append/sharing, local SOCKS proxy static/dynamic port/UDP/auth, mux, sniffing, log level and routing strategy persist; VPN DNS feeds Harmony `VpnConfig.dnsAddresses`, IPv6 preference feeds the VPN interface address/route and generated Xray outbound Happy Eyeballs, proxy sharing changes local HTTP/SOCKS inbound listen, dynamic SOCKS port resolves a free runtime port before start, remote/domestic DNS feed generated Xray DNS, DNS hosts accepts v2rayNG `domain:address,...` format into `dns.hosts`, mux/XUDP/fragment advanced fields feed outbound runtime settings, and log level now uses a dedicated picker. Remaining gaps are deeper platform-specific settings and full device regression. |
| PerAppProxyActivity | Apps | Partial. Toggle, allowlist/blocklist mode, preset/manual package list, and VPN `blockedApplications`/`trustedApplications` mapping are wired; unrestricted installed-app enumeration is platform-limited. |
| UserAssetActivity / UserAssetUrlActivity / BackupActivity | Assets | Present. geoip/geosite download (Loyalsoldier rules), custom asset URL CRUD, clipboard backup/restore, WebDAV ZIP cloud backup/restore, and native Geo count status are implemented. |
| LogcatActivity | Logs | Present. App diagnostic logs and native runtime stats are visible. |
| AboutActivity | About | Present. Harmony-specific about/license note. |
| TaskerActivity / shortcuts / widgets / QS tile | Platform equivalents | Pending. Android-only entry points need Harmony shortcuts/widgets equivalents. |
| UrlSchemeActivity | Import entry | Present. Harmony Want/deep-link import handles subscription and config links. |

## Business Function Map

| Function | Current status |
| --- | --- |
| Subscription URL fetch and parse | Present for `vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`, `http://`, `https://`, `wireguard://`, `hysteria2://`, `hy2://`. |
| Node select and save current profile | Present. |
| Xray config generation | Present for outbound + native TUN inbound + metrics inbound + optional local HTTP/SOCKS proxy inbounds/listen sharing + dynamic local SOCKS runtime port + proxy-chain multi-hop outbounds via `sockopt.dialerProxy` + policy-group `routing.balancers`/observatory generation + basic direct/block outbounds. Existing ordinary outbound nodes can be converted into proxy-chain/policy-group JSON through Add > advanced config; policy groups can resolve members dynamically from the latest subscription group and node-name regex filter at startup; full custom Xray configs are validated and passed through unchanged at runtime. |
| Persistent app settings | Present for core VPN, DNS, DNS hosts, IPv6, mux/XUDP/fragment, sniffing, log and routing strategy; selected values are applied at connection start, including VPN interface DNS, generated Xray `dns.hosts`, IPv6 routing, outbound Happy Eyeballs, mux settings, and outbound fragment settings. |
| VPN Extension start/stop | Present, with emulator timeout diagnostics. Real-device verified for IPv4 data path (2026-06-15); IPv6 interface address/route generation is wired and awaits real-device regression. |
| Xray native TUN runtime | Present in HAP via `CGoSetTunFd` + Xray TUN inbound. Real-device closed loop verified (2026-06-15): TUN → Xray → outbound → reachable. |
| VMess/VLESS/Trojan/Shadowsocks parsing | Present. |
| SOCKS/HTTP/WireGuard/Hysteria2 parsing | Present for share-link import, subscription discovery, and manual outbound editing; WireGuard `[Interface]/[Peer]` `.conf` text/file import is also supported. Runtime connection for WireGuard/Hysteria2 still needs core validation. |
| TUIC parsing | Pending. |
| Delay test / real ping / sort by delay | Present. Per-node real outbound delay via libXray `CGoPing` (own SOCKS test inbound, preferring `CGoGetFreePorts` dynamic ports with 10825 fallback), persisted per node, with sort-by-delay. Falls back to direct URL test when the native core is unavailable (e.g. emulator). Needs real-device validation. |
| Delete all / duplicate / invalid configs | Present for the active subscription group. Delete-all, duplicate cleanup, and invalid-node cleanup are wired from the Nodes menu. |
| Export/share configs and QR generation | Present for text-oriented flows. Plain-text share-link/exported JSON output is present, full custom configs export as JSON text, node detail can render QR codes for share-link nodes, Export can save the current group to a `.txt` file, and batch/single-node text can be sent through the Harmony system share sheet with clipboard fallback. |
| Multi-subscription groups | Present with legacy single-subscription migration. Rename/edit, enable-disable, delete, reorder, batch update all, per-subscription insecure URL opt-in, auto-update opt-in, and update interval are wired. Foreground due refresh is wired, and subscription fetches can prefer the local HTTP proxy when the VPN runtime exposes it. Background refresh remains pending. |
| Routing rulesets and geo assets | Partial. Geo asset download/management present (Assets page), with native geosite/geoip count sidecars shown in file status after core rebuild. Clipboard backup/restore and WebDAV ZIP cloud backup/restore are wired, with legacy JSON backup restore compatibility. Routing config emits metrics, ad-block, custom enabled rules, and bypass-LAN/CN rules in order. Predefined ruleset import/export is wired; proxy-chain and policy-group runtime nodes are supported through JSON import and the advanced outbound builder, routing rules can target the current advanced outbound, and policy-group subscription-regex dynamic members resolve at startup. |
| Per-app proxy | Partial. VPN app allow/block mapping is wired from saved package names; unrestricted installed-app enumeration remains platform-limited. |
| Auto subscription update | Partial. Per-subscription `autoUpdate` and `updateIntervalMinutes` persist with v2rayNG-compatible defaults (1440 minutes, minimum 15), and the home page performs throttled foreground due refresh through the local HTTP proxy when available. Harmony background scheduling remains pending. |
| Boot/startup automation | Pending and platform-dependent. |

## Native Bridge Status

`libxray.so` exports 13 CGo functions; `napi_init.cpp` wires 12 (M1, refreshed 2026-06-18).

- Wired (runtime): `CGoRunXrayFromJSON`, `CGoStopXray`, `CGoPing`, `CGoSetTunFd`.
- Wired (M1): `CGoQueryStats` (real per-tag traffic via the Xray metrics
  `/debug/vars` endpoint), `CGoTestXray` (pre-connect config preflight),
  `CGoXrayVersion` (core version on the About page),
  `CGoReadGeoFiles` / `CGoCountGeoData` (Geo file validation/count status on Assets),
  `CGoGetFreePorts` (dynamic ports for real outbound delay tests and local SOCKS runtime port),
  `CGoConvertShareLinksToXrayJson` / `CGOConvertXrayJsonToShareLinks`
  (native share text ⇄ Xray JSON conversion).
- Idle: `CGoRunXray`.

> M1 note: the prebuilt `libxray.so` version script previously exported only the
> 4 runtime symbols (`local: *` hid the rest). `scripts/build_libxray_ohos.sh`
> now also exports `CGoQueryStats`/`CGoTestXray`/`CGoXrayVersion` plus the Geo
> count/read symbols, `CGoGetFreePorts`, and the share conversion symbols, so
> the bridge code is complete but a
> **`libxray.so` rebuild + device retest** is required before these optional
> paths take effect. Until then the bridge degrades gracefully (stats fall back,
> preflight is skipped, version shows the static label, Geo count reports
> unavailable, delay tests and dynamic local SOCKS use static fallback ports,
> and import falls back to the built-in single-link parser only).
