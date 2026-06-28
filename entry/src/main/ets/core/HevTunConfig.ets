import { HevTunLogLevel } from './Profile';

// 默认读写超时（毫秒），与 DEFAULT_HEV_TUN_RW_TIMEOUT='300,60'（秒）一致的回退值。
const DEFAULT_TCP_TIMEOUT_MS: number = 300000;
const DEFAULT_UDP_TIMEOUT_MS: number = 60000;

// 把设置里的 hevTunRwTimeout（'tcp,udp' 两个秒数，如 '300,60'）解析成毫秒。
// 解析失败的分量回退到默认值；hev 的 yaml 用毫秒。
function parseTimeoutsMs(rwTimeout: string): [number, number] {
  const parts = rwTimeout.split(',');
  const tcpSec = parts.length > 0 ? Number(parts[0].trim()) : NaN;
  const udpSec = parts.length > 1 ? Number(parts[1].trim()) : NaN;
  const tcpMs = Number.isInteger(tcpSec) && tcpSec > 0 ? tcpSec * 1000 : DEFAULT_TCP_TIMEOUT_MS;
  const udpMs = Number.isInteger(udpSec) && udpSec > 0 ? udpSec * 1000 : DEFAULT_UDP_TIMEOUT_MS;
  return [tcpMs, udpMs];
}

// 生成 hev-socks5-tunnel 的 yaml 配置串（交给 startNativeHevTun → hev_socks5_tunnel_main_from_str）。
// TUN fd 不在 yaml 里，由原生 API 参数单独传。socks5.udp='udp' 表示 UDP-over-UDP 转发。
//
// ⚠️ 字段名以钉死的 hev 版本（build_hev_ohos.sh 的 HEV_PIN）为准；若上游改了 yaml schema，
//    需同步本函数与构建脚本。
export function buildHevTunConfigYaml(
  mtu: number,
  socksHost: string,
  socksPort: number,
  logLevel: HevTunLogLevel,
  rwTimeout: string
): string {
  const timeouts = parseTimeoutsMs(rwTimeout);
  const tcpMs = timeouts[0];
  const udpMs = timeouts[1];
  const lines: string[] = [
    'tunnel:',
    `  mtu: ${mtu}`,
    'socks5:',
    `  address: ${socksHost}`,
    `  port: ${socksPort}`,
    "  udp: 'udp'",
    'misc:',
    `  log-level: ${logLevel}`,
    `  tcp-read-write-timeout: ${tcpMs}`,
    `  udp-read-write-timeout: ${udpMs}`,
    ''
  ];
  return lines.join('\n');
}
