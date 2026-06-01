# Hey VPN Native Core

`libheyvpn.so` is the ArkTS N-API bridge. It loads two native libraries packaged
beside it:

- `libxray.so`: built from XTLS/libXray with cgo exports. Required symbols:
  - `CGoRunXrayFromJSON(const char* base64Request) -> char*`
  - `CGoStopXray() -> char*`
- `libheytun2socks.so`: a Harmony adapter around xjasonlyu/tun2socks v2.
  Required symbols:
  - `HeyTun2SocksStart(int tunFd, const char* socksHost, int socksPort, int mtu) -> int`
  - `HeyTun2SocksStop() -> void`
  - optional `HeyTun2SocksUploadBytes() -> int64_t`
  - optional `HeyTun2SocksDownloadBytes() -> int64_t`

Build them from the project root:

```shell
./scripts/build_libxray_ohos.sh
./scripts/build_tun2socks_ohos.sh
```

The scripts place outputs in `entry/src/main/cpp/prebuilt/arm64-v8a/`. CMake
copies any prebuilt core libraries into the HAP native library directory after
building `libheyvpn.so`.

Note: the current Go toolchain does not expose `GOOS=ohos`. The scripts use
`GOOS=linux GOARCH=arm64` with DevEco's `aarch64-unknown-linux-ohos-clang` as
the cgo compiler. The libraries build and export the expected OHOS-linked ELF
symbols, but device validation is still required because Go runtime behavior is
not officially advertised as an OHOS target.
