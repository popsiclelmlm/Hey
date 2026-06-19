export const V2RAYNG_FLOW_OPTIONS: Array<string> = [
  'none',
  'xtls-rprx-vision',
  'xtls-rprx-vision-udp443'
];

export const V2RAYNG_UTLS_FINGERPRINT_OPTIONS: Array<string> = [
  'none',
  'chrome',
  'firefox',
  'safari',
  'ios',
  'android',
  'edge',
  '360',
  'qq',
  'random',
  'randomized'
];

export const V2RAYNG_DEFAULT_VMESS_SECURITY: string = 'chacha20-poly1305';

export const V2RAYNG_VMESS_SECURITY_OPTIONS: Array<string> = [
  V2RAYNG_DEFAULT_VMESS_SECURITY,
  'aes-128-gcm',
  'auto',
  'none',
  'zero'
];

export const V2RAYNG_SS_SECURITY_OPTIONS: Array<string> = [
  'aes-256-gcm',
  'aes-128-gcm',
  'chacha20-poly1305',
  'chacha20-ietf-poly1305',
  'xchacha20-poly1305',
  'xchacha20-ietf-poly1305',
  'none',
  'plain',
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305'
];

export const V2RAYNG_SUPPORTED_TRANSPORT_OPTIONS: Array<string> = [
  'tcp',
  'kcp',
  'ws',
  'httpupgrade',
  'xhttp',
  'h2',
  'grpc'
];

export const V2RAYNG_TCP_HEADER_TYPE_OPTIONS: Array<string> = [
  'none',
  'http'
];

export const V2RAYNG_KCP_HEADER_TYPE_OPTIONS: Array<string> = [
  'none',
  'srtp',
  'utp',
  'wechat-video',
  'dtls',
  'wireguard',
  'dns'
];

export const V2RAYNG_XHTTP_MODE_OPTIONS: Array<string> = [
  'auto',
  'packet-up',
  'stream-up',
  'stream-one'
];

export const V2RAYNG_GRPC_MODE_OPTIONS: Array<string> = [
  'gun',
  'multi'
];

export const V2RAYNG_CORE_LOG_LEVEL_OPTIONS: Array<string> = [
  'debug',
  'info',
  'warning',
  'error',
  'none'
];

export const V2RAYNG_DEFAULT_CORE_LOG_LEVEL: string = 'warning';

export function normalizeV2rayNgCoreLogLevel(value: string, fallback: string = V2RAYNG_DEFAULT_CORE_LOG_LEVEL): string {
  const trimmed = value.trim();
  if (V2RAYNG_CORE_LOG_LEVEL_OPTIONS.indexOf(trimmed) >= 0) {
    return trimmed;
  }
  if (V2RAYNG_CORE_LOG_LEVEL_OPTIONS.indexOf(fallback) >= 0) {
    return fallback;
  }
  return V2RAYNG_DEFAULT_CORE_LOG_LEVEL;
}

export const V2RAYNG_FRAGMENT_PACKET_OPTIONS: Array<string> = [
  'tlshello',
  '1-2',
  '1-3',
  '1-5'
];

export const V2RAYNG_DEFAULT_FRAGMENT_PACKETS: string = 'tlshello';

export function normalizeV2rayNgFragmentPackets(value: string, fallback: string = V2RAYNG_DEFAULT_FRAGMENT_PACKETS): string {
  const trimmed = value.trim();
  if (V2RAYNG_FRAGMENT_PACKET_OPTIONS.indexOf(trimmed) >= 0) {
    return trimmed;
  }
  return fallback;
}
