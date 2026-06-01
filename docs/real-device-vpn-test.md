# Real Device VPN Closed Loop Test

This checklist verifies the current MVP path:

`VpnExtensionAbility -> TUN fd -> libheytun2socks.so -> 127.0.0.1:10808 SOCKS -> libxray.so outbound`

## Build and Install

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk ./scripts/device_vpn_smoke_test.sh build
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk ./scripts/device_vpn_smoke_test.sh install
```

If command-line install rejects the unsigned HAP, install from DevEco Studio with a valid debug signing config.

## Log Watch

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk ./scripts/device_vpn_smoke_test.sh logs
```

Expected tags:

- `HeyVpnAbility`: VPN authorization, TUN fd, lifecycle cleanup.
- `HeyNative`: `dlopen`, `dlsym`, Xray start/stop, tun2socks start/stop.
- In-app Logs panel: mirrored diagnostic events from the VPN extension plus periodic native stats.

## Manual Closed Loop

1. Open Hey on the device.
2. Paste a subscription URL or a single VLESS/REALITY link.
3. Select one node and tap Start.
4. Accept the system VPN authorization dialog.
5. Confirm the in-app log sequence:
   - `VPN ability created.`
   - `VPN created. tunFd=<number>`
   - `Xray started.`
   - `tun2socks started.`
   - repeated `Native bridge stats.`
6. Open another app, such as the system browser, and visit a site that requires the proxy.
7. Return to Hey and confirm upload/download counters increase.
8. Tap Stop and confirm:
   - `tun2socks stop requested.`
   - `Xray stop requested.`
   - `VPN destroyed.`
   - the system VPN icon disappears.

## Failure Signals

- `dlopen libxray.so failed`: the packaged Go shared library is not accepted by the device runtime or was not packaged.
- `dlsym libxray.so failed`: exported symbols changed; verify `CGoRunXrayFromJSON` and `CGoStopXray`.
- `tun2socks adapter start failed`: the TUN fd path may not be compatible with the adapter on this device.
- VPN starts but traffic never increases: check whether the browser traffic is really routed through the VPN and whether the app's own bundle exclusion is avoiding Xray socket loops.
