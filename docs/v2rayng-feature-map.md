# v2rayNG Feature Parity Map

This project targets feature parity with the local Android reference at
`/Users/liumin/Documents/v2rayNG/V2rayNG` without copying Android/Kotlin source,
XML layouts, drawable assets, launcher artwork, strings, or package branding.

## Page Map

| Android reference area | Harmony page | Current status |
| --- | --- | --- |
| MainActivity / MainRecyclerAdapter | Nodes | Present. Lists subscription nodes, search, select current node, start/stop/restart VPN. |
| Add config menu | Add | Present. Imports share links, outbound JSON, or subscription URL; protocol tabs are scaffolded. |
| ScannerActivity / ScScannerActivity | Scan | Present. Paste/import path is wired; camera QR capture still pending. |
| SubSettingActivity / SubEditActivity | Subs | Multi-group model present. Save/update/select/enable-disable/delete are wired; dedicated edit form and reorder pending. |
| ServerActivity protocol editors | Add | Scaffolded for VLESS, VMess, Shadowsocks, SOCKS, HTTP, Trojan, WireGuard, Hysteria2. Field-level editors pending. |
| ServerCustomConfigActivity | Add | Raw outbound JSON import works. Full custom config import pending. |
| RoutingSettingActivity / RoutingEditActivity | Route | Scaffolded. Strategy selection is local; ruleset persistence and config generation pending. |
| SettingsActivity | Config | Scaffolded. Core, VPN, UI, mux, fragment, subscription and advanced settings need persistence/config wiring. |
| PerAppProxyActivity | Apps | Scaffolded. Harmony bundle enumeration and blocked/allowed app mapping pending. |
| UserAssetActivity / UserAssetUrlActivity | Assets | Scaffolded. Geo asset download, URL management and backup/restore pending. |
| LogcatActivity | Logs | Present. App diagnostic logs and native runtime stats are visible. |
| AboutActivity | About | Present. Harmony-specific about/license note. |
| TaskerActivity / shortcuts / widgets / QS tile | Platform equivalents | Pending. Android-only entry points need Harmony shortcuts/widgets equivalents. |
| UrlSchemeActivity | Import entry | Pending. Harmony Want/deep-link import route needed. |

## Business Function Map

| Function | Current status |
| --- | --- |
| Subscription URL fetch and parse | Present for `vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`, `http://`, `https://`, `wireguard://`, `hysteria2://`, `hy2://`. |
| Node select and save current profile | Present. |
| Xray config generation | Present for outbound + local SOCKS inbound + basic direct/block outbounds. |
| VPN Extension start/stop | Present, with emulator timeout diagnostics. Needs real-device validation. |
| Xray executable + tun2socks adapter | Present in HAP. Needs real-device closed-loop verification. |
| VMess/VLESS/Trojan/Shadowsocks parsing | Present. |
| SOCKS/HTTP/WireGuard/Hysteria2 parsing | Present for share-link import and subscription discovery. Runtime connection for WireGuard/Hysteria2 still needs core validation. |
| TUIC parsing | Pending. |
| Delay test / real ping / sort by delay | Pending. |
| Delete all / duplicate / invalid configs | Pending. |
| Export/share configs and QR generation | Pending. |
| Multi-subscription groups | Present with legacy single-subscription migration. Rename/reorder and batch update all pending. |
| Routing rulesets and geo assets | Pending. |
| Per-app proxy | Pending. |
| Auto subscription update | Pending. |
| Boot/startup automation | Pending and platform-dependent. |
