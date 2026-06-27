/**
 * 内置 Xray 内核（xtls/xray-core）的版本号 —— 即 `core.Version()` 的返回值。
 *
 * 此常量在重新编译 libxray.so 时由 scripts/build_libxray_ohos.sh 从所锁定的
 * xtls/xray-core 源码（core/core.go 的 Version_x/y/z 常量）自动写入，
 * 与 prebuilt/arm64-v8a/libxray.so 保持同步——请勿手动修改。
 */
export const BUNDLED_XRAY_VERSION: string = '25.8.3';

/**
 * 内置 sing-box 内核（sagernet/sing-box）的版本号。
 *
 * 来源：libsingbox/go.mod 钉定的 sing-box 版本。About 页直接读这个编译期常量，
 * 避免为了显示版本号触发一次原生冷调用。
 */
export const BUNDLED_SINGBOX_VERSION: string = '1.11.0';
