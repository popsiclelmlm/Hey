import { AppLanguage, ConnectionStatus } from '../core/Profile';
import { formatTranslation, translate } from '../core/I18n';
import { formatClockTime } from './Formatters';

export function formatOne(language: AppLanguage, key: string, name: string, value: string): string {
  const names = new Array<string>();
  const values = new Array<string>();
  names.push(name);
  values.push(value);
  return formatTranslation(language, key, names, values);
}

export function formatTwo(language: AppLanguage, key: string, name1: string, value1: string, name2: string, value2: string): string {
  const names = new Array<string>();
  const values = new Array<string>();
  names.push(name1);
  values.push(value1);
  names.push(name2);
  values.push(value2);
  return formatTranslation(language, key, names, values);
}

export function localizedConnectionStatus(language: AppLanguage, status: ConnectionStatus): string {
  switch (status) {
    case ConnectionStatus.STARTING:
      return translate(language, 'status.starting');
    case ConnectionStatus.RUNNING:
      return translate(language, 'status.running');
    case ConnectionStatus.STOPPING:
      return translate(language, 'status.stopping');
    case ConnectionStatus.ERROR:
      return translate(language, 'status.error');
    default:
      return translate(language, 'status.idle');
  }
}

export function localizedProfileSavedText(language: AppLanguage, updatedAt: number): string {
  if (updatedAt <= 0) {
    return translate(language, 'profile.notSaved');
  }
  return formatOne(language, 'profile.savedAt', 'time', formatClockTime(updatedAt));
}

export function localizedSubscriptionStatusText(language: AppLanguage, updatedAt: number): string {
  if (updatedAt <= 0) {
    return translate(language, 'subscription.none');
  }
  return formatOne(language, 'subscription.updatedAt', 'time', formatClockTime(updatedAt));
}

export function localizeCoreMessage(language: AppLanguage, message: string): string {
  if (message.length === 0) {
    return '';
  }
  if (message === 'Native bridge not queried yet.' ||
    message === translate('zh', 'runtime.nativeBridgeNotQueried') ||
    message === translate('en', 'runtime.nativeBridgeNotQueried')) {
    return translate(language, 'runtime.nativeBridgeNotQueried');
  }
  if (message === 'VPN extension owns the native bridge. Xray is handling the TUN inbound directly.' ||
    message === translate('zh', 'runtime.vpnOwnsBridge') ||
    message === translate('en', 'runtime.vpnOwnsBridge')) {
    return translate(language, 'runtime.vpnOwnsBridge');
  }
  if (message === '请先粘贴 Xray outbound JSON。') {
    return translate(language, 'core.emptyOutbound');
  }
  if (message === 'outbound 缺少 protocol 字段。') {
    return translate(language, 'core.missingProtocol');
  }
  if (message === 'outbound 缺少 settings 字段。') {
    return translate(language, 'core.missingSettings');
  }
  if (message === '请先粘贴 Xray 完整配置 JSON。') {
    return translate(language, 'core.emptyFullConfig');
  }
  if (message === '完整配置缺少 inbounds 数组。') {
    return translate(language, 'core.missingFullConfigInbounds');
  }
  if (message === '完整配置缺少 outbounds 数组。') {
    return translate(language, 'core.missingFullConfigOutbounds');
  }
  if (message === '完整 Xray 配置校验通过。') {
    return translate(language, 'core.validFullConfig');
  }
  if (message === '请先粘贴代理链 JSON。') {
    return translate(language, 'core.emptyProxyChainConfig');
  }
  if (message === '代理链配置缺少 outbounds 数组。') {
    return translate(language, 'core.missingProxyChainOutbounds');
  }
  if (message === '代理链至少需要两个 outbound。') {
    return translate(language, 'core.insufficientProxyChainOutbounds');
  }
  if (message === '代理链配置校验通过。') {
    return translate(language, 'core.validProxyChainConfig');
  }
  if (message === '请先粘贴策略组 JSON。') {
    return translate(language, 'core.emptyPolicyGroupConfig');
  }
  if (message === '策略组配置缺少 outbounds 数组。') {
    return translate(language, 'core.missingPolicyGroupOutbounds');
  }
  if (message === '策略组至少需要一个 outbound。') {
    return translate(language, 'core.emptyPolicyGroupOutbounds');
  }
  if (message === '策略组配置校验通过。') {
    return translate(language, 'core.validPolicyGroupConfig');
  }
  if (message === '暂只支持 vless://、vmess://、trojan://、ss://、socks://、http://、wireguard:// 和 hysteria2:// 分享链接。') {
    return translate(language, 'core.unsupportedShareLink');
  }
  if (message === 'VLESS 链接缺少用户 ID。') {
    return translate(language, 'core.vlessMissingId');
  }
  if (message === 'VMess 链接缺少服务器、端口或用户 ID。') {
    return translate(language, 'core.vmessMissingServer');
  }
  if (message === 'VMess 链接缺少用户 ID。') {
    return translate(language, 'core.vmessMissingId');
  }
  if (message === 'Trojan 链接缺少密码。') {
    return translate(language, 'core.trojanMissingPassword');
  }
  if (message === 'Shadowsocks 链接缺少加密方法或密码。') {
    return translate(language, 'core.ssMissingMethod');
  }
  if (message === 'Shadowsocks legacy 链接格式不正确。') {
    return translate(language, 'core.ssLegacyInvalid');
  }
  if (message === 'WireGuard 链接缺少私钥。') {
    return translate(language, 'core.wgMissingPrivateKey');
  }
  if (message === 'WireGuard 链接缺少 publickey。') {
    return translate(language, 'core.wgMissingPublicKey');
  }
  if (message === 'WireGuard 配置缺少 endpoint。') {
    return translate(language, 'core.wgMissingEndpoint');
  }
  if (message === 'WireGuard 配置文件导入成功。') {
    return translate(language, 'core.wgConfigImported');
  }
  if (message === 'Hysteria2 链接缺少认证密码。') {
    return translate(language, 'core.hy2MissingPassword');
  }
  if (message === '订阅链接必须是 http:// 或 https://。') {
    return translate(language, 'subscription.urlMustHttp');
  }
  if (message === 'HTTP 订阅链接不安全，请开启允许不安全订阅链接后重试。') {
    return translate(language, 'subscription.insecureUrlBlocked');
  }
  if (message === '订阅内容里没有识别到支持的节点。') {
    return translate(language, 'subscription.noSupportedNodes');
  }
  if (message === '启动 VPN 超时：系统 VPN 授权服务没有响应。若 hilog 中出现 com.huawei.hmos.vpndialog bundle not exist，说明当前系统镜像缺少 VPN 授权组件，请改用真机测试。') {
    return translate(language, 'vpn.startTimeout');
  }

  const unsupportedPrefix = '暂不支持 ';
  const unsupportedEnd = '，当前支持 VLESS、VMess、Trojan、Shadowsocks、SOCKS、HTTP、WireGuard 和 Hysteria2。';
  if (message.startsWith(unsupportedPrefix) && message.endsWith(unsupportedEnd)) {
    const protocol = message.substring(unsupportedPrefix.length, message.length - unsupportedEnd.length);
    return formatOne(language, 'core.unsupportedProtocol', 'protocol', protocol);
  }

  const validSuffix = ' outbound 校验通过。';
  if (message.endsWith(validSuffix)) {
    const protocol = message.substring(0, message.length - validSuffix.length);
    return formatOne(language, 'core.validOutbound', 'protocol', protocol);
  }

  const proxyChainHopPrefix = '代理链第 ';
  const proxyChainHopMiddle = ' 跳无效：';
  const proxyChainHopMiddleIndex = message.indexOf(proxyChainHopMiddle);
  if (message.startsWith(proxyChainHopPrefix) && proxyChainHopMiddleIndex > proxyChainHopPrefix.length) {
    const index = message.substring(proxyChainHopPrefix.length, proxyChainHopMiddleIndex);
    const error = message.substring(proxyChainHopMiddleIndex + proxyChainHopMiddle.length);
    return formatTwo(language, 'core.invalidProxyChainHop', 'index', index, 'error', localizeCoreMessage(language, error));
  }

  const policyGroupMemberPrefix = '策略组第 ';
  const policyGroupMemberMiddle = ' 个成员无效：';
  const policyGroupMemberMiddleIndex = message.indexOf(policyGroupMemberMiddle);
  if (message.startsWith(policyGroupMemberPrefix) && policyGroupMemberMiddleIndex > policyGroupMemberPrefix.length) {
    const index = message.substring(policyGroupMemberPrefix.length, policyGroupMemberMiddleIndex);
    const error = message.substring(policyGroupMemberMiddleIndex + policyGroupMemberMiddle.length);
    return formatTwo(language, 'core.invalidPolicyGroupMember', 'index', index, 'error', localizeCoreMessage(language, error));
  }

  const shareSuffix = ' 分享链接导入成功。';
  if (message.endsWith(shareSuffix)) {
    const protocol = message.substring(0, message.length - shareSuffix.length);
    return formatOne(language, 'core.shareImported', 'protocol', protocol);
  }

  const updatePrefix = '订阅更新完成，共 ';
  const updateSuffix = ' 个可用节点。';
  if (message.startsWith(updatePrefix) && message.endsWith(updateSuffix)) {
    const count = message.substring(updatePrefix.length, message.length - updateSuffix.length);
    return formatOne(language, 'subscription.updateComplete', 'count', count);
  }

  return localizePrefixMessage(language, message, 'JSON 解析失败：', 'core.jsonParseFailed') ??
    localizePrefixMessage(language, message, '分享链接解析失败：', 'core.shareParseFailed') ??
    localizePrefixMessage(language, message, '启动 VPN 失败：', 'vpn.startFailed') ??
    localizePrefixMessage(language, message, '停止 VPN 失败：', 'vpn.stopFailed') ??
    message;
}

function localizePrefixMessage(language: AppLanguage, message: string, prefix: string, key: string): string | null {
  if (!message.startsWith(prefix)) {
    return null;
  }
  return formatOne(language, key, 'error', message.substring(prefix.length));
}
