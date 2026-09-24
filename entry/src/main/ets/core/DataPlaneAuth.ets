import { VPN_DATA_SOCKS_HOST, VPN_DATA_SOCKS_PORT } from './XrayConfig';

/**
 * VPN 数据面（tun2socks / hev → 内核本地 SOCKS 入站）的会话凭据。
 *
 * 数据面入站固定监听 127.0.0.1:VPN_DATA_SOCKS_PORT。不加认证时，设备上任何应用都能直连它，
 * 借隧道出网、绕过分应用规则。每次启动 VPN 生成一组随机凭据，只写进交给 VPN 扩展的那份配置
 * 和数据面引擎：不落盘、不进日志、不进 generatedConfig 快照。
 */
export interface DataPlaneCredentials {
  username: string;
  password: string;
}

export interface SecuredDataPlaneConfig {
  configJson: string;
  // 没找到 Hey 生成的数据面入站（如自带 inbounds 的完整配置）时为 undefined：配置原样返回，
  // 引擎也不带凭据——tun2socks 带凭据时只提供用户名密码认证，对无认证入站会握手失败。
  credentials?: DataPlaneCredentials;
}

type JsonField = Object | string | number | boolean | undefined;
type JsonObject = Record<string, JsonField>;

interface XraySocksAccount {
  user: string;
  pass: string;
}

interface SingboxSocksUser {
  username: string;
  password: string;
}

// 与 XrayConfig 的 tunInbound、SingboxConfig 的 socksIn 保持一致。
const XRAY_DATA_PLANE_INBOUND_TAG: string = 'tun-in';
const SINGBOX_DATA_PLANE_INBOUND_TAG: string = 'socks-in';
const USERNAME_BYTES: number = 8;
const PASSWORD_BYTES: number = 16;

export const DATA_PLANE_RANDOM_BYTES: number = USERNAME_BYTES + PASSWORD_BYTES;

// 随机字节由调用方用系统安全随机源生成；这里只做切分和十六进制编码（十六进制无需任何转义）。
export function credentialsFromRandomBytes(bytes: Uint8Array): DataPlaneCredentials {
  if (bytes.length < DATA_PLANE_RANDOM_BYTES) {
    throw new Error(`data plane credentials need ${DATA_PLANE_RANDOM_BYTES} random bytes.`);
  }
  return {
    username: toHex(bytes, 0, USERNAME_BYTES),
    password: toHex(bytes, USERNAME_BYTES, DATA_PLANE_RANDOM_BYTES)
  };
}

export function secureDataPlaneInbound(configJson: string, useSingbox: boolean, credentials: DataPlaneCredentials): SecuredDataPlaneConfig {
  let config: JsonObject;
  try {
    const parsed = JSON.parse(configJson) as JsonField;
    if (!isJsonObject(parsed)) {
      return { configJson };
    }
    config = parsed as JsonObject;
  } catch (error) {
    return { configJson };
  }

  const inbounds = config['inbounds'];
  if (!Array.isArray(inbounds)) {
    return { configJson };
  }
  for (let index = 0; index < inbounds.length; index++) {
    const item = inbounds[index] as JsonField;
    if (!isJsonObject(item)) {
      continue;
    }
    const inbound = item as JsonObject;
    const applied = useSingbox ? addSingboxUser(inbound, credentials) : addXrayAccount(inbound, credentials);
    if (applied) {
      return { configJson: JSON.stringify(config), credentials };
    }
  }
  return { configJson };
}

// libheytun2socks.so 只导出 HeyTun2SocksStart(fd, host, port, mtu)，适配层按 "socks5://%s:%d" 拼代理 URL，
// tun2socks 再从 URL 的 userinfo 取用户名密码。把凭据放进 host 即可，不必重编 .so。
export function tun2socksProxyHost(host: string, credentials?: DataPlaneCredentials): string {
  if (credentials === undefined) {
    return host;
  }
  return `${credentials.username}:${credentials.password}@${host}`;
}

function addXrayAccount(inbound: JsonObject, credentials: DataPlaneCredentials): boolean {
  if (inbound['tag'] !== XRAY_DATA_PLANE_INBOUND_TAG || inbound['protocol'] !== 'socks' ||
    inbound['listen'] !== VPN_DATA_SOCKS_HOST || inbound['port'] !== VPN_DATA_SOCKS_PORT) {
    return false;
  }
  const rawSettings = inbound['settings'];
  const settings: JsonObject = isJsonObject(rawSettings) ? rawSettings as JsonObject : {};
  const accounts = new Array<JsonField>();
  const existing = settings['accounts'];
  if (settings['auth'] === 'password' && Array.isArray(existing)) {
    for (let index = 0; index < existing.length; index++) {
      accounts.push(existing[index] as JsonField);
    }
  }
  const account: XraySocksAccount = { user: credentials.username, pass: credentials.password };
  accounts.push(account);
  settings['auth'] = 'password';
  settings['accounts'] = accounts;
  inbound['settings'] = settings;
  return true;
}

function addSingboxUser(inbound: JsonObject, credentials: DataPlaneCredentials): boolean {
  const type = inbound['type'];
  if (inbound['tag'] !== SINGBOX_DATA_PLANE_INBOUND_TAG || (type !== 'mixed' && type !== 'socks') ||
    inbound['listen'] !== VPN_DATA_SOCKS_HOST || inbound['listen_port'] !== VPN_DATA_SOCKS_PORT) {
    return false;
  }
  const users = new Array<JsonField>();
  const existing = inbound['users'];
  if (Array.isArray(existing)) {
    for (let index = 0; index < existing.length; index++) {
      users.push(existing[index] as JsonField);
    }
  }
  const user: SingboxSocksUser = { username: credentials.username, password: credentials.password };
  users.push(user);
  inbound['users'] = users;
  return true;
}

function isJsonObject(value: JsonField): boolean {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function toHex(bytes: Uint8Array, start: number, end: number): string {
  let hex = '';
  for (let index = start; index < end; index++) {
    hex += bytes[index].toString(16).padStart(2, '0');
  }
  return hex;
}
