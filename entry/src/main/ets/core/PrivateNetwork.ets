// Loopback / private IPv4 network detection.
//
// Mirrors v2rayNG `AppConfig.PRIVATE_IP_LIST`, `Utils.isIpInCidr` and the host
// check in `Utils.isValidSubUrl`: a plaintext HTTP subscription URL is treated
// as safe (no insecure toggle required) when it targets loopback or a private
// network host. v2rayNG's `isIpInCidr` is IPv4-only (32-bit mask math), and
// `PRIVATE_IP_LIST` only contains IPv4 ranges, so this mirror is IPv4-only too.

const LOOPBACK_IPV4: string = '127.0.0.1';

const DECIMAL_OCTET: RegExp = /^[0-9]+$/;

export const PRIVATE_IP_LIST: Array<string> = [
  '0.0.0.0/8',
  '10.0.0.0/8',
  '127.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '169.254.0.0/16',
  '224.0.0.0/4'
];

function parseIpv4ToLong(ip: string): number {
  const octets = ip.split('.');
  if (octets.length !== 4) {
    return -1;
  }
  let result = 0;
  for (let index = 0; index < octets.length; index++) {
    const text = octets[index];
    if (text.length === 0 || !DECIMAL_OCTET.test(text)) {
      return -1;
    }
    const octet = Number(text);
    if (octet < 0 || octet > 255) {
      return -1;
    }
    result = (result * 256) + octet;
  }
  return result;
}

// IPv4 CIDR containment check, mirroring v2rayNG `Utils.isIpInCidr` (IPv4 only).
export function isIpv4InCidr(ip: string, cidr: string): boolean {
  const slash = cidr.indexOf('/');
  if (slash < 0) {
    return false;
  }
  const prefixText = cidr.substring(slash + 1);
  if (prefixText.length === 0 || !DECIMAL_OCTET.test(prefixText)) {
    return false;
  }
  const prefixLength = Number(prefixText);
  if (prefixLength > 32) {
    return false;
  }
  const ipLong = parseIpv4ToLong(ip);
  const cidrLong = parseIpv4ToLong(cidr.substring(0, slash));
  if (ipLong < 0 || cidrLong < 0) {
    return false;
  }
  if (prefixLength === 0) {
    return true;
  }
  const mask = (0xFFFFFFFF << (32 - prefixLength)) >>> 0;
  return ((ipLong & mask) >>> 0) === ((cidrLong & mask) >>> 0);
}

// Whether an already-extracted host is a loopback/private IPv4 address.
export function isLoopbackOrPrivateIpv4Host(host: string): boolean {
  if (parseIpv4ToLong(host) < 0) {
    return false;
  }
  for (let index = 0; index < PRIVATE_IP_LIST.length; index++) {
    if (isIpv4InCidr(host, PRIVATE_IP_LIST[index])) {
      return true;
    }
  }
  return false;
}

function extractUrlHost(url: string): string {
  const schemeIndex = url.indexOf('://');
  if (schemeIndex < 0) {
    return '';
  }
  let authority = url.substring(schemeIndex + 3);
  const terminators: Array<string> = ['/', '?', '#'];
  for (let index = 0; index < terminators.length; index++) {
    const position = authority.indexOf(terminators[index]);
    if (position >= 0) {
      authority = authority.substring(0, position);
    }
  }
  const at = authority.lastIndexOf('@');
  if (at >= 0) {
    authority = authority.substring(at + 1);
  }
  if (authority.startsWith('[')) {
    const close = authority.indexOf(']');
    return close > 0 ? authority.substring(1, close) : authority.substring(1);
  }
  const colon = authority.indexOf(':');
  return colon >= 0 ? authority.substring(0, colon) : authority;
}

// Mirrors v2rayNG `Utils.isValidSubUrl`: a plaintext HTTP subscription URL is
// safe without the insecure toggle when it targets loopback or a private host.
export function isLoopbackOrPrivateHttpUrl(url: string): boolean {
  const trimmed = url.trim();
  if (trimmed.indexOf(LOOPBACK_IPV4) >= 0) {
    return true;
  }
  return isLoopbackOrPrivateIpv4Host(extractUrlHost(trimmed));
}
