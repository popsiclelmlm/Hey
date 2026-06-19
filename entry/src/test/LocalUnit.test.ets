import { describe, it, expect } from '@ohos/hypium';
import { buildPolicyGroupConfigFromNodes, buildPolicyGroupConfigFromSubscription, buildProxyChainConfigFromNodes, isAdvancedOutboundBuildableNode, normalizePolicyGroupBuilderStrategy, parseAdvancedOutboundEditState, resolveDynamicPolicyGroupConfigJson } from '../main/ets/core/AdvancedOutboundBuilder';
import { buildAppBackupPayload, buildAppBackupZipFromPayload, parseAppBackupData, parseAppBackupPayload } from '../main/ets/core/AppBackup';
import { CONTROL_CARD_FORM_NAME, CONTROL_CARD_SCAN_URI, CONTROL_CARD_START_URI, CONTROL_CARD_STOP_URI, CONTROL_CARD_TOGGLE_URI, buildControlCardFormData } from '../main/ets/core/ControlCard';
import { AssetNameEntry, hasDuplicateAssetName, isEditableCustomAssetUrl, normalizeScannedAssetUrl } from '../main/ets/core/AssetUrls';
import { decodeBase64ToUtf8 } from '../main/ets/core/Encoding';
import { formatTranslation, missingTranslationKeys, normalizeLanguage, resolveLanguage, resolveSystemLanguage, translate } from '../main/ets/core/I18n';
import { resolveImportedNodeName } from '../main/ets/core/ImportedNodeNames';
import { defaultJsonConfigNodeName, resolveJsonConfigNodeName } from '../main/ets/core/JsonConfigNames';
import { selectRuntimeLocalSocksPort, shouldUseDynamicLocalSocksPort, withRuntimeLocalSocksPort } from '../main/ets/core/LocalProxy';
import { parseManualOutboundEditState } from '../main/ets/core/ManualOutboundEditState';
import { buildManualHysteria2Outbound, buildManualWireguardOutbound } from '../main/ets/core/ManualOutboundBuilder';
import { ANDROID_PACKAGE_NAME_LIST_URL, clearVisiblePerAppPackages, exportPerAppProxyList, importPerAppProxyList, invertVisiblePerAppPackages, normalizePerAppPackageList, resolveAutoProxyPackageListContent, selectAllPerAppPackages, selectAutoProxyPackages } from '../main/ets/core/PerAppProxy';
import { APP_MODE_PROXY_ONLY, APP_MODE_VPN, AppSettings, ConnectionStatus, DEFAULT_DELAY_TEST_URL, DEFAULT_IP_API_URL, DEFAULT_VPN_MTU, OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS, OUTBOUND_DOMAIN_RESOLVE_NONE, OUTBOUND_DOMAIN_RESOLVE_REPLACE, OutboundDomainResolveMethod, normalizeAppRuntimeMode, normalizeRealPingConcurrency, normalizeRoutingDomainStrategy, normalizeUiModeNight, ProxyNode, resolveDelayTestUrl, RoutingRule, RuntimeStats, SubscriptionGroup } from '../main/ets/core/Profile';
import { BUILTIN_GEO_DATA_FILE_NAMES, GEOIP_ONLY_CN_PRIVATE_FILE_NAME, GEOIP_ONLY_CN_PRIVATE_URL, GEO_FILE_SOURCES, V2RAYNG_GEO_FILE_SOURCE_REPOS, buildBuiltinGeoAssetUrl, formatGeoCountSummary, formatGeoCountUnavailable, geoDataSpecForFile, parseGeoCountData } from '../main/ets/core/GeoAssets';
import { DELAY_TEST_SOCKS_PORT, LOCAL_HTTP_PROXY_LAN_HOST, LOCAL_HTTP_PROXY_PORT, LOCAL_SOCKS_PROXY_PORT, UNIDENTIFIED_PROCESS_PACKAGE, buildDelayTestConfig, buildRuntimeXrayConfig, buildXrayConfig, buildXrayConfigWithSettings, collectOutboundDomainPreResolveHosts, normalizeFullConfigRoutingProcesses, normalizeOutboundInput, normalizeRoutingRuleProcesses, validateFullConfigJson, validateOutboundJson, validatePolicyGroupConfigJson, validateProxyChainConfigJson, withOutboundDomainResolvedHosts } from '../main/ets/core/XrayConfig';
import { parseDeepLink } from '../main/ets/core/DeepLink';
import { HARMONY_SEND_DATA_ACTION, HARMONY_SHARE_ABSTRACT_KEY, HARMONY_SHARE_URL_KEY, HARMONY_TEXT_MIME_TYPE, SharedTextWantLike, extractSharedTextFromWant, isSharedTextWant } from '../main/ets/core/SharedTextImport';
import { extractOutboundsFromXrayConfig } from '../main/ets/core/XrayOutbounds';
import { SUPPORTED_SHARE_LINK_SCHEMES, buildUnsupportedShareLinkMessage, formatOutboundJsonToShareLink, isSupportedShareLink, parseShareLinkToOutboundJson } from '../main/ets/core/ShareLinkParser';
import { exportRoutingRulesJson, importRoutingRulesJson, resetRoutingRulesFromPreset } from '../main/ets/core/RoutingRules';
import { decideRuntimeSettingsRestart } from '../main/ets/core/SettingsChange';
import {
  DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  isSubscriptionAutoUpdateDue,
  moveSubscriptionGroup,
  normalizeSubscriptionUpdateInterval
} from '../main/ets/core/SubscriptionGroups';
import { buildSubscriptionAutoUpdateSchedulePlan } from '../main/ets/core/SubscriptionSchedulerPlan';
import { buildSpeedNotificationAdditionalText, buildSpeedNotificationText, calculateSpeedNotificationRates, sampleSpeedNotificationStats, shouldPublishSpeedNotification } from '../main/ets/core/SpeedNotification';
import { DEFAULT_WEBDAV_BACKUP_FILE_NAME, buildWebDavAuthorizationHeader, buildWebDavMkcolUrls, buildWebDavRemoteUrl, isWebDavMkcolAcceptedStatus, normalizeWebDavConfig, validateWebDavConfig } from '../main/ets/core/WebDav';
import { CURRENT_APP_VERSION, buildUpdateCheckResult, compareVersions, normalizeVersionTag } from '../main/ets/core/UpdateChecker';
import { V2RAYNG_CORE_LOG_LEVEL_OPTIONS, V2RAYNG_DEFAULT_CORE_LOG_LEVEL, V2RAYNG_DEFAULT_FRAGMENT_PACKETS, V2RAYNG_DEFAULT_MUX_XUDP_QUIC, V2RAYNG_DEFAULT_STREAM_ALPN, V2RAYNG_DEFAULT_VMESS_SECURITY, V2RAYNG_FLOW_OPTIONS, V2RAYNG_FRAGMENT_PACKET_OPTIONS, V2RAYNG_GRPC_MODE_OPTIONS, V2RAYNG_KCP_HEADER_TYPE_OPTIONS, V2RAYNG_MUX_XUDP_QUIC_OPTIONS, V2RAYNG_SS_SECURITY_OPTIONS, V2RAYNG_STREAM_ALPN_OPTIONS, V2RAYNG_SUPPORTED_TRANSPORT_OPTIONS, V2RAYNG_TCP_HEADER_TYPE_OPTIONS, V2RAYNG_UTLS_FINGERPRINT_OPTIONS, V2RAYNG_VMESS_SECURITY_OPTIONS, V2RAYNG_XHTTP_MODE_OPTIONS, normalizeV2rayNgCoreLogLevel, normalizeV2rayNgFragmentPackets, normalizeV2rayNgMuxXudpQuic, normalizeV2rayNgStreamAlpn, normalizeV2rayNgStreamAlpnWithFallback } from '../main/ets/core/V2rayNgOptions';
import { filterLogItems, formatLogcatText } from '../main/ets/features/logs/LogOperations';
import {
  applyDelayTestPostActionsToGroups,
  buildNodeExportModel,
  buildNodeFullConfigModel,
  dedupeNodes,
  dedupeVisibleNodesInGroups,
  exportNodesText,
  filterNodes,
  findInvalidNodes,
  removeVisibleNodesFromGroups,
  removeVisibleTestFailedNodesFromGroups,
  sortGroupsByDelayTargets,
  sortNodes
} from '../main/ets/features/nodes/NodeOperations';
import { SETTINGS_CONTROLLER } from '../main/ets/features/settings/SettingsController';
import { normalizeIpApiUrl, parseRemoteIpInfoContent } from '../main/ets/services/RemoteIpInfo';
import { SubscriptionManager } from '../main/ets/services/SubscriptionManager';
import { buildTextShareWant } from '../main/ets/services/SystemShare';
import { DEFAULT_APP_SETTINGS } from '../main/ets/storage/SettingsStore';
import { formatBytes, formatDuration } from '../main/ets/utils/Formatters';
import { formatOne, localizedProfileSavedText, localizeCoreMessage } from '../main/ets/utils/LocalizationPresenter';
import { BUNDLE_NAME, createDefaultVpnConfig } from '../main/ets/vpn/VpnConstants';

const VLESS_REALITY_OUTBOUND: string =
  '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.example.com","publicKey":"test-public-key","shortId":"abcd","fingerprint":"chrome"}}}';
const TROJAN_OUTBOUND: string =
  '{"protocol":"trojan","tag":"relay","settings":{"servers":[{"address":"relay.example.com","port":443,"password":"secret"}]}}';
const VMESS_TCP_OUTBOUND: string =
  '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"vmess.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"vmess.example.com"}}}';
const VLESS_XHTTP_OUTBOUND: string =
  '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"xhttp.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none"}]}]},"streamSettings":{"network":"xhttp","security":"tls","xhttpSettings":{"path":"/xhttp","host":"cdn.example.com"}}}';
const VLESS_FINALMASK_OUTBOUND: string =
  '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"fm.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none"}]}]},"streamSettings":{"network":"ws","security":"tls","finalmask":{"tcp":[{"type":"custom-fragment"}]}}}';
const PROXY_CHAIN_CONFIG: string =
  `{"remarks":"chain-demo","outbounds":[${VLESS_REALITY_OUTBOUND},${TROJAN_OUTBOUND}]}`;
const POLICY_GROUP_CONFIG: string =
  `{"type":"policy-group","remarks":"group-demo","strategy":"roundRobin","outbounds":[${VLESS_REALITY_OUTBOUND},${TROJAN_OUTBOUND}]}`;
const FULL_XRAY_CONFIG: string =
  '{"remarks":"Custom full config","log":{"loglevel":"info"},"inbounds":[{"tag":"tun-in","protocol":"tun","settings":{"name":"vpn-tun","mtu":1400}}],"outbounds":[{"tag":"direct","protocol":"freedom","settings":{}}],"routing":{"domainStrategy":"AsIs","rules":[]}}';
const WIREGUARD_CONF: string =
  '[Interface]\nPrivateKey = private-key\nAddress = 172.16.0.2/32, fd00::2/128\nMTU = 1420\n\n[Peer]\nPublicKey = peer-key\nPresharedKey = shared-key\nEndpoint = wg.example.com:51820\nReserved = 1,2,3\nAllowedIPs = 0.0.0.0/0, ::/0\n';
const WIREGUARD_CONF_WITHOUT_RESERVED: string =
  '[Interface]\nPrivateKey = private-key\nAddress = 172.16.0.2/32\nMTU = 1420\n\n[Peer]\nPublicKey = peer-key\nEndpoint = wg.example.com:51820\nAllowedIPs = 0.0.0.0/0\n';
const WIREGUARD_CONF_WITHOUT_MTU: string =
  '[Interface]\nPrivateKey = private-key\nAddress = 172.16.0.2/32\n\n[Peer]\nPublicKey = peer-key\nEndpoint = wg.example.com:51820\nAllowedIPs = 0.0.0.0/0\n';

export default function localUnitTest() {
  describe('settingsChange', () => {
    it('decides when runtime settings changes should restart the service', 0, () => {
      const idle = decideRuntimeSettingsRestart(false, true, false);
      expect(idle.shouldRestart).assertFalse();
      expect(idle.keepPending).assertFalse();

      const stopped = decideRuntimeSettingsRestart(true, false, false);
      expect(stopped.shouldRestart).assertFalse();
      expect(stopped.keepPending).assertFalse();

      const busy = decideRuntimeSettingsRestart(true, true, true);
      expect(busy.shouldRestart).assertFalse();
      expect(busy.keepPending).assertTrue();

      const running = decideRuntimeSettingsRestart(true, true, false);
      expect(running.shouldRestart).assertTrue();
      expect(running.keepPending).assertFalse();
    });
  });

  describe('importedNodeNames', () => {
    it('resolves imported node names with shared priority', 0, () => {
      expect(resolveImportedNodeName('{"tag":"  Primary  ","remarks":"Remark","name":"Name"}', 'Fallback')).assertEqual('Primary');
      expect(resolveImportedNodeName('{"remarks":"  Remark  ","name":"Name"}', 'Fallback')).assertEqual('Remark');
      expect(resolveImportedNodeName('{"name":"  Name  "}', 'Fallback')).assertEqual('Name');
      expect(resolveImportedNodeName('{"protocol":"vless"}', '  Scan Fallback  ')).assertEqual('Scan Fallback');
      expect(resolveImportedNodeName('{', '')).assertEqual('链接导入');
    });
  });

  describe('xrayConfig', () => {
    it('validates vless reality outbound json', 0, () => {
      const result = validateOutboundJson(VLESS_REALITY_OUTBOUND);
      expect(result.valid).assertTrue();
      expect(result.protocol).assertEqual('vless');
      expect(result.normalizedJson).assertContain('"protocol": "vless"');
    });

    it('rejects malformed json', 0, () => {
      const result = validateOutboundJson('{');
      expect(result.valid).assertFalse();
    });

    it('rejects outbound without settings', 0, () => {
      const result = validateOutboundJson('{"protocol":"vless"}');
      expect(result.valid).assertFalse();
      expect(result.message).assertContain('settings');
    });

    it('builds full xray config with tun inbound', 0, () => {
      const result = buildXrayConfig(VLESS_REALITY_OUTBOUND);
      expect(result.configJson).assertContain('"inbounds"');
      expect(result.configJson).assertContain('"outbounds"');
      expect(result.configJson).assertContain('"protocol": "tun"');
      expect(result.configJson).assertContain('"tag": "tun-in"');
      expect(result.configJson).assertContain('"security": "reality"');
    });

    it('validates full custom xray config json', 0, () => {
      const directValidation = validateFullConfigJson(FULL_XRAY_CONFIG);
      expect(directValidation.valid).assertTrue();
      expect(directValidation.protocol).assertEqual('custom');
      expect(directValidation.configType).assertEqual('full');
      expect(directValidation.normalizedJson).assertContain('"inbounds"');

      const autoValidation = normalizeOutboundInput(FULL_XRAY_CONFIG);
      expect(autoValidation.valid).assertTrue();
      expect(autoValidation.configType).assertEqual('full');
      expect(autoValidation.message).assertEqual('完整 Xray 配置校验通过。');
    });

    it('validates and builds proxy chain xray config', 0, () => {
      const validation = validateProxyChainConfigJson(PROXY_CHAIN_CONFIG);
      expect(validation.valid).assertTrue();
      expect(validation.protocol).assertEqual('proxy-chain');
      expect(validation.configType).assertEqual('proxy-chain');
      expect(validation.normalizedJson).assertContain('"remarks": "chain-demo"');

      const autoValidation = normalizeOutboundInput(PROXY_CHAIN_CONFIG);
      expect(autoValidation.valid).assertTrue();
      expect(autoValidation.configType).assertEqual('proxy-chain');
      expect(validateProxyChainConfigJson(`{"outbounds":[${VLESS_REALITY_OUTBOUND}]}`).valid).assertFalse();
      expect(localizeCoreMessage('en', '代理链至少需要两个 outbound。')).assertEqual('Proxy chain needs at least two outbounds.');
      expect(localizeCoreMessage('en', '代理链第 2 跳无效：outbound 缺少 settings 字段。')).assertEqual('Proxy chain hop 2 is invalid: outbound is missing the settings field.');

      const speedSettings = buildSettingsFixture();
      speedSettings.speedEnabled = true;
      const result = buildRuntimeXrayConfig(validation.normalizedJson, speedSettings, 'proxy-chain');
      expect(result.configJson).assertContain('"tag": "proxy"');
      expect(result.configJson).assertContain('"tag": "proxy-chain-1"');
      expect(result.configJson).assertContain('"dialerProxy": "proxy-chain-1"');
      expect(result.configJson).assertContain('"protocol": "trojan"');
      expect(result.configJson).assertContain('"tag": "direct"');
      expect(result.metricsServer !== undefined).assertTrue();
    });

    it('validates and builds policy group balancer config', 0, () => {
      const validation = validatePolicyGroupConfigJson(POLICY_GROUP_CONFIG);
      expect(validation.valid).assertTrue();
      expect(validation.protocol).assertEqual('policy-group');
      expect(validation.configType).assertEqual('policy-group');
      expect(validation.normalizedJson).assertContain('"strategy": "roundRobin"');

      const autoValidation = normalizeOutboundInput(POLICY_GROUP_CONFIG);
      expect(autoValidation.valid).assertTrue();
      expect(autoValidation.configType).assertEqual('policy-group');
      expect(validatePolicyGroupConfigJson('{"type":"policy-group","outbounds":[]}').valid).assertFalse();
      expect(localizeCoreMessage('en', '策略组至少需要一个 outbound。')).assertEqual('Policy group needs at least one outbound.');
      expect(localizeCoreMessage('en', '策略组第 1 个成员无效：outbound 缺少 protocol 字段。')).assertEqual('Policy group member 1 is invalid: outbound is missing the protocol field.');

      const settings = buildSettingsFixture();
      settings.localSocksEnabled = true;
      settings.appendHttpProxy = true;
      const result = buildRuntimeXrayConfig(validation.normalizedJson, settings, 'policy-group');
      expect(result.configJson).assertContain('"tag": "proxy-policy-group-1"');
      expect(result.configJson).assertContain('"tag": "proxy-policy-group-2"');
      expect(result.configJson).assertContain('"tag": "balancer"');
      expect(result.configJson).assertContain('"selector": [');
      expect(result.configJson).assertContain('"proxy-policy-group-"');
      expect(result.configJson).assertContain('"type": "roundRobin"');
      expect(result.configJson).assertContain('"balancerTag": "balancer"');
      expect(hasInboundBalancerRule(result.configJson, 'http-in', 'balancer')).assertTrue();
      expect(result.httpProxyPort).assertEqual(LOCAL_HTTP_PROXY_PORT);

      settings.delayTestUrl = 'https://probe.example/generate_204';
      const leastPing = buildRuntimeXrayConfig(`{"type":"policy-group","outbounds":[${VLESS_REALITY_OUTBOUND}]}`, settings, 'policy-group');
      expect(leastPing.configJson).assertContain('"probeUrl": "https://probe.example/generate_204"');
      const leastLoad = buildRuntimeXrayConfig(`{"type":"policy-group","policyGroupType":"1","outbounds":[${VLESS_REALITY_OUTBOUND}]}`, settings, 'policy-group');
      expect(leastLoad.configJson).assertContain('"type": "leastLoad"');
      expect(leastLoad.configJson).assertContain('"burstObservatory"');
      expect(leastLoad.configJson).assertContain('"destination": "https://probe.example/generate_204"');
    });

    it('builds proxy chain and policy group configs from existing outbound nodes', 0, () => {
      const nodes = buildAdvancedNodeFixture();
      const chain = buildProxyChainConfigFromNodes('Chain A', nodes);
      expect(chain.success).assertTrue();
      expect(chain.configType).assertEqual('proxy-chain');
      expect(chain.protocol).assertEqual('proxy-chain');
      expect(chain.count).assertEqual(2);
      expect(chain.configJson).assertContain('"remarks": "Chain A"');
      expect(chain.configJson).assertContain('"protocol": "vless"');
      expect(chain.configJson).assertContain('"protocol": "trojan"');
      expect(validateProxyChainConfigJson(chain.configJson).valid).assertTrue();
      expect(buildRuntimeXrayConfig(chain.configJson, buildSettingsFixture(), 'proxy-chain').configJson).assertContain('"dialerProxy": "proxy-chain-1"');

      const group = buildPolicyGroupConfigFromNodes('Group A', '1', nodes);
      expect(group.success).assertTrue();
      expect(group.configType).assertEqual('policy-group');
      expect(group.protocol).assertEqual('policy-group');
      expect(group.configJson).assertContain('"remarks": "Group A"');
      expect(group.configJson).assertContain('"strategy": "leastLoad"');
      expect(validatePolicyGroupConfigJson(group.configJson).valid).assertTrue();
      expect(buildRuntimeXrayConfig(group.configJson, buildSettingsFixture(), 'policy-group').configJson).assertContain('"burstObservatory"');

      expect(normalizePolicyGroupBuilderStrategy('0')).assertEqual('leastPing');
      expect(normalizePolicyGroupBuilderStrategy('random')).assertEqual('random');
      expect(normalizePolicyGroupBuilderStrategy('bad')).assertEqual('roundRobin');
      expect(localizeCoreMessage('en', '代理链至少需要两个普通 outbound 节点。')).assertEqual('Proxy chain needs at least two regular outbound nodes.');
    });

    it('builds dynamic policy group configs from subscription filters', 0, () => {
      const nodes = buildAdvancedNodeFixture();
      const firstGroup = buildSubscriptionGroupFixture('sub-a', 'A');
      firstGroup.nodes = [nodes[0]];
      const secondGroup = buildSubscriptionGroupFixture('sub-b', 'B');
      secondGroup.nodes = [nodes[1]];

      const allMembers = buildPolicyGroupConfigFromSubscription('All Dynamic', 'roundRobin', '', '', [firstGroup, secondGroup]);
      expect(allMembers.success).assertTrue();
      expect(allMembers.count).assertEqual(2);
      expect(allMembers.configJson).assertContain('"policyGroupSubscriptionId": ""');
      expect(allMembers.configJson).assertContain('"policyGroupFilter": ""');
      expect(validatePolicyGroupConfigJson(allMembers.configJson).valid).assertTrue();

      const filtered = buildPolicyGroupConfigFromSubscription('Filtered Dynamic', 'random', 'sub-a', 'VLESS', [firstGroup, secondGroup]);
      expect(filtered.success).assertTrue();
      expect(filtered.count).assertEqual(1);
      expect(filtered.configJson).assertContain('"policyGroupSubscriptionId": "sub-a"');
      expect(filtered.configJson).assertContain('"policyGroupFilter": "VLESS"');
      expect(filtered.configJson).assertContain('"strategy": "random"');
      expect(filtered.configJson).assertContain('"protocol": "vless"');
      expect(filtered.configJson.indexOf('"protocol": "trojan"')).assertEqual(-1);
      expect(validatePolicyGroupConfigJson(filtered.configJson).valid).assertTrue();
    });

    it('parses existing advanced outbound configs for v2rayNG-style editing', 0, () => {
      const nodes = buildAdvancedNodeFixture();
      const chain = buildProxyChainConfigFromNodes('Editable Chain', nodes);
      expect(chain.success).assertTrue();

      const chainEdit = parseAdvancedOutboundEditState(chain.configJson, 'proxy-chain');
      expect(chainEdit.success).assertTrue();
      expect(chainEdit.mode).assertEqual('proxy-chain');
      expect(chainEdit.name).assertEqual('Editable Chain');
      expect(chainEdit.memberOutboundJsons.length).assertEqual(2);
      expect(chainEdit.memberOutboundJsons[0]).assertContain('"protocol": "vless"');
      expect(chainEdit.memberOutboundJsons[1]).assertContain('"protocol": "trojan"');
      expect(chainEdit.dynamicPolicyGroupEnabled).assertFalse();

      const firstGroup = buildSubscriptionGroupFixture('sub-a', 'A');
      firstGroup.nodes = nodes;
      const dynamicGroup = buildPolicyGroupConfigFromSubscription('Editable Dynamic', 'leastPing', 'sub-a', 'VLESS', [firstGroup]);
      expect(dynamicGroup.success).assertTrue();

      const groupEdit = parseAdvancedOutboundEditState(dynamicGroup.configJson, 'policy-group');
      expect(groupEdit.success).assertTrue();
      expect(groupEdit.mode).assertEqual('policy-group');
      expect(groupEdit.name).assertEqual('Editable Dynamic');
      expect(groupEdit.strategy).assertEqual('leastPing');
      expect(groupEdit.dynamicPolicyGroupEnabled).assertTrue();
      expect(groupEdit.dynamicSubscriptionId).assertEqual('sub-a');
      expect(groupEdit.dynamicFilter).assertEqual('VLESS');
      expect(groupEdit.memberOutboundJsons.length).assertEqual(1);
    });

    it('resolves dynamic policy group configs from latest subscription groups', 0, () => {
      const nodes = buildAdvancedNodeFixture();
      const initialGroup = buildSubscriptionGroupFixture('sub-a', 'A');
      initialGroup.nodes = [nodes[0]];
      const dynamic = buildPolicyGroupConfigFromSubscription('Latest Dynamic', 'leastPing', 'sub-a', 'Advanced', [initialGroup]);
      expect(dynamic.success).assertTrue();
      expect(dynamic.configJson).assertContain('"protocol": "vless"');

      const latestGroup = buildSubscriptionGroupFixture('sub-a', 'A');
      latestGroup.nodes = [nodes[1]];
      const resolved = resolveDynamicPolicyGroupConfigJson(dynamic.configJson, [latestGroup]);
      expect(resolved).assertContain('"protocol": "trojan"');
      expect(resolved.indexOf('"protocol": "vless"')).assertEqual(-1);
      expect(resolved).assertContain('"policyGroupSubscriptionId": "sub-a"');
      expect(buildRuntimeXrayConfig(resolved, buildSettingsFixture(), 'policy-group').configJson).assertContain('"proxy-policy-group-1"');
      expect(resolveDynamicPolicyGroupConfigJson(POLICY_GROUP_CONFIG, [latestGroup])).assertEqual(POLICY_GROUP_CONFIG);
    });

    it('rejects advanced outbound builders with nested or invalid nodes', 0, () => {
      const nodes = buildAdvancedNodeFixture();
      const fullConfigNode = copyNode(nodes[0], 'full-config');
      fullConfigNode.protocol = 'custom';
      fullConfigNode.configType = 'full';
      fullConfigNode.outboundJson = FULL_XRAY_CONFIG;
      expect(isAdvancedOutboundBuildableNode(fullConfigNode)).assertFalse();

      const invalidNode = copyNode(nodes[0], 'invalid-json');
      invalidNode.outboundJson = '{';
      expect(isAdvancedOutboundBuildableNode(invalidNode)).assertFalse();
      expect(buildProxyChainConfigFromNodes('bad', [nodes[0], invalidNode]).success).assertFalse();
      expect(buildPolicyGroupConfigFromNodes('bad', 'roundRobin', [fullConfigNode]).message).assertContain('普通 outbound');
      expect(localizeCoreMessage('en', '第 2 个节点不是可用的普通 outbound，不能加入高级节点。')).assertEqual('Node 2 is not a valid regular outbound and cannot be used in an advanced node.');

      const nestedChain = buildProxyChainConfigFromNodes('nested-source', nodes);
      const nestedNode = copyNode(nodes[0], 'nested-chain');
      nestedNode.protocol = 'proxy-chain';
      nestedNode.configType = 'proxy-chain';
      nestedNode.outboundJson = nestedChain.configJson;
      expect(isAdvancedOutboundBuildableNode(nestedNode)).assertFalse();
      expect(buildProxyChainConfigFromNodes('bad-nested', [nodes[0], nestedNode]).success).assertFalse();
      expect(buildProxyChainConfigFromNodes('', [nodes[0]]).count).assertEqual(1);
    });

    it('extracts importable outbounds from native-converted xray config', 0, () => {
      const configJson = '{"outbounds":[{"tag":"alpha","protocol":"vless","settings":{"vnext":[]}},{"remarks":"Beta","protocol":"trojan","settings":{"servers":[]}},{"tag":"skip","protocol":"freedom"}]}';
      const extracted = extractOutboundsFromXrayConfig(configJson);
      expect(extracted.length).assertEqual(2);
      expect(extracted[0].name).assertEqual('alpha');
      expect(extracted[0].protocol).assertEqual('vless');
      expect(extracted[0].outboundJson).assertContain('"protocol": "vless"');
      expect(extracted[1].name).assertEqual('Beta');
      expect(extractOutboundsFromXrayConfig('{"outbound":{"name":"single","protocol":"socks","settings":{}}}')[0].name).assertEqual('single');
    });

    it('builds manual wireguard and hysteria2 outbounds', 0, () => {
      const wireguard = buildManualWireguardOutbound({
        tag: 'WG',
        host: '2001:db8::1',
        port: '51820',
        secretKey: 'private-key',
        publicKey: 'public-key',
        preSharedKey: 'shared-key',
        localAddress: '172.16.0.2/32, fd00::2/128',
        reserved: '1,2,3',
        mtu: '1420'
      });
      expect(wireguard.success).assertTrue();
      expect(wireguard.outboundJson).assertContain('"protocol": "wireguard"');
      expect(wireguard.outboundJson).assertContain('"endpoint": "[2001:db8::1]:51820"');
      expect(wireguard.outboundJson).assertContain('"reserved"');
      expect(validateOutboundJson(wireguard.outboundJson).valid).assertTrue();
      const defaultReservedWireguard = buildManualWireguardOutbound({
        tag: 'WG',
        host: 'wg.example.com',
        port: '51820',
        secretKey: 'private-key',
        publicKey: 'public-key',
        preSharedKey: '',
        localAddress: '',
        reserved: '',
        mtu: ''
      });
      expect(defaultReservedWireguard.success).assertTrue();
      const reservedSection = jsonArraySection(defaultReservedWireguard.outboundJson, 'reserved');
      expect(reservedSection).assertContain('"reserved": [');
      expect(countTextOccurrences(reservedSection, '0')).assertEqual(3);
      expect(buildManualWireguardOutbound({
        tag: 'WG',
        host: 'example.com',
        port: '51820',
        secretKey: '',
        publicKey: 'public-key',
        preSharedKey: '',
        localAddress: '',
        reserved: '',
        mtu: ''
      }).success).assertFalse();

      const hysteria2 = buildManualHysteria2Outbound({
        tag: 'HY2',
        host: 'hy2.example.com',
        port: '443',
        password: 'secret',
        sni: 'cdn.example.com',
        alpn: 'h3',
        allowInsecure: true,
        obfsPassword: 'obfs-secret',
        portHopping: '20000-50000',
        portHoppingInterval: '10-60',
        pinSHA256: 'hy2-pinned-sha256',
        bandwidthDown: '100 mbps',
        bandwidthUp: '20 mbps'
      });
      expect(hysteria2.success).assertTrue();
      expect(hysteria2.outboundJson).assertContain('"protocol": "hysteria2"');
      expect(hysteria2.outboundJson).assertContain('"alpn": "h3"');
      expect(hysteria2.outboundJson).assertContain('"portHopping": "20000-50000"');
      expect(hysteria2.outboundJson).assertContain('"portHoppingInterval": "10-60"');
      expect(hysteria2.outboundJson).assertContain('"pinSHA256": "hy2-pinned-sha256"');
      expect(hysteria2.outboundJson).assertContain('"obfsPassword": "obfs-secret"');
      expect(hysteria2.outboundJson).assertContain('"bandwidthDown": "100 mbps"');
      expect(hysteria2.outboundJson).assertContain('"bandwidthUp": "20 mbps"');
      expect(validateOutboundJson(hysteria2.outboundJson).valid).assertTrue();
      expect(buildManualHysteria2Outbound({
        tag: 'HY2',
        host: 'hy2.example.com',
        port: '443',
        password: '',
        sni: '',
        alpn: '',
        allowInsecure: false,
        obfsPassword: '',
        portHopping: '',
        portHoppingInterval: '',
        pinSHA256: '',
        bandwidthDown: '',
        bandwidthUp: ''
      }).success).assertFalse();

      const defaultAlpnHysteria2 = buildManualHysteria2Outbound({
        tag: 'HY2',
        host: 'hy2.example.com',
        port: '443',
        password: 'secret',
        sni: '',
        alpn: '',
        allowInsecure: false,
        obfsPassword: '',
        portHopping: '',
        portHoppingInterval: '',
        pinSHA256: '',
        bandwidthDown: '',
        bandwidthUp: ''
      });
      expect(defaultAlpnHysteria2.success).assertTrue();
      expect(defaultAlpnHysteria2.outboundJson).assertContain('"alpn": "h3"');
    });

    it('parses manual outbound configs back into NodeEdit state', 0, () => {
      const vless = parseManualOutboundEditState(
        '{"protocol":"vless","tag":"Manual VLESS","settings":{"vnext":[{"address":"edit.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none","flow":"xtls-rprx-vision-udp443"}]}]},"streamSettings":{"network":"xhttp","security":"reality","xhttpSettings":{"path":"/x","host":"cdn.example.com","mode":"packet-up","extra":{"headers":{"x-test":"1"}}},"realitySettings":{"serverName":"reality.example.com","publicKey":"pub","shortId":"abcd","spiderX":"/bot","mldsa65Verify":"pqv","fingerprint":"randomized","echConfigList":"ech","pinnedPeerCertSha256":"pcs"},"finalmask":{"tcp":[{"type":"custom"}]}}}',
        'Node Name',
        'vless'
      );
      expect(vless.valid).assertTrue();
      expect(vless.protocol).assertEqual('vless');
      expect(vless.nodeName).assertEqual('Node Name');
      expect(vless.serverHost).assertEqual('edit.example.com');
      expect(vless.vlessFlow).assertEqual('xtls-rprx-vision-udp443');
      expect(vless.transportType).assertEqual('xhttp');
      expect(vless.transportXhttpMode).assertEqual('packet-up');
      expect(vless.transportXhttpExtra).assertContain('"x-test": "1"');
      expect(vless.tlsSecurity).assertEqual('reality');
      expect(vless.realitySpiderX).assertEqual('/bot');
      expect(vless.realityMldsa65Verify).assertEqual('pqv');
      expect(vless.tlsFingerprint).assertEqual('randomized');
      expect(vless.tlsEchConfigList).assertEqual('ech');
      expect(vless.tlsPinnedPeerCertSha256).assertEqual('pcs');
      expect(vless.transportFinalMask).assertContain('"custom"');

      const kcp = parseManualOutboundEditState(
        '{"protocol":"vmess","tag":"KCP","settings":{"vnext":[{"address":"kcp.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"kcp","kcpSettings":{"mtu":1200,"tti":30},"finalmask":{"udp":[{"type":"header-dns","settings":{"domain":"dns.example.com"}},{"type":"mkcp-aes128gcm","settings":{"password":"seed"}}]}}}',
        '',
        'vmess'
      );
      expect(kcp.valid).assertTrue();
      expect(kcp.protocol).assertEqual('vmess');
      expect(kcp.transportType).assertEqual('kcp');
      expect(kcp.transportKcpHeaderType).assertEqual('dns');
      expect(kcp.transportHost).assertEqual('dns.example.com');
      expect(kcp.transportPath).assertEqual('seed');
      expect(kcp.transportKcpMtu).assertEqual('1200');
      expect(kcp.transportKcpTti).assertEqual('30');

      const wireguard = parseManualOutboundEditState(
        '{"protocol":"wireguard","tag":"WG","settings":{"secretKey":"private","address":["172.16.0.2/32","fd00::2/128"],"reserved":[1,2,3],"mtu":1420,"peers":[{"publicKey":"public","preSharedKey":"shared","endpoint":"[2001:db8::1]:51820"}]}}',
        '',
        'wireguard'
      );
      expect(wireguard.valid).assertTrue();
      expect(wireguard.protocol).assertEqual('wireguard');
      expect(wireguard.serverHost).assertEqual('2001:db8::1');
      expect(wireguard.serverPort).assertEqual('51820');
      expect(wireguard.wgPublicKey).assertEqual('public');
      expect(wireguard.wgPreSharedKey).assertEqual('shared');
      expect(wireguard.wgReserved).assertEqual('1,2,3');
      expect(wireguard.wgLocalAddress).assertEqual('172.16.0.2/32,fd00::2/128');

      const hysteria2 = parseManualOutboundEditState(
        '{"protocol":"hysteria2","tag":"HY2","settings":{"servers":[{"address":"hy.example.com","port":443,"password":"secret","sni":"sni.example.com","alpn":"h3","insecure":true,"obfsPassword":"obfs","portHopping":"20000-50000","portHoppingInterval":"10-60","pinSHA256":"pin","bandwidthDown":"100 mbps","bandwidthUp":"20 mbps"}]}}',
        '',
        'hysteria2'
      );
      expect(hysteria2.valid).assertTrue();
      expect(hysteria2.protocol).assertEqual('hysteria2');
      expect(hysteria2.tlsSni).assertEqual('sni.example.com');
      expect(hysteria2.tlsAllowInsecure).assertTrue();
      expect(hysteria2.hy2ObfsPassword).assertEqual('obfs');
      expect(hysteria2.hy2PortHoppingInterval).assertEqual('10-60');
      expect(hysteria2.hy2PinSha256).assertEqual('pin');
      expect(hysteria2.hy2BandwidthDown).assertEqual('100 mbps');
    });

    it('builds runtime config from full custom config without wrapping', 0, () => {
      const settings = buildSettingsFixture();
      settings.logLevel = 'debug';
      settings.appendHttpProxy = true;
      const result = buildRuntimeXrayConfig(FULL_XRAY_CONFIG, settings, 'full');
      expect(result.configJson).assertContain('"loglevel": "info"');
      expect(result.configJson).assertContain('"protocol": "tun"');
      expect(result.configJson.indexOf('"metrics"')).assertEqual(-1);
      expect(result.configJson.indexOf('"http-in"')).assertEqual(-1);
      expect(result.httpProxyPort === undefined).assertTrue();

      const fullWithProcess = '{"inbounds":[],"outbounds":[{"tag":"direct","protocol":"freedom","settings":{}}],"routing":{"rules":[{"type":"field","process":["com.example.app"],"outboundTag":"direct"},{"type":"field","process":["com.missing.app"],"outboundTag":"direct"}]}}';
      const normalizedFull = normalizeFullConfigRoutingProcesses(
        fullWithProcess,
        (packageName: string): string | undefined => packageName === 'com.example.app' ? '10123' : undefined
      );
      expect(normalizedFull).assertContain('"10123"');
      expect(normalizedFull.indexOf('com.example.app')).assertEqual(-1);
      expect(normalizedFull).assertContain('com.missing.app');
    });

    it('resolves editable json config node names', 0, () => {
      expect(resolveJsonConfigNodeName(VLESS_REALITY_OUTBOUND, 'outbound')).assertEqual('proxy');
      expect(resolveJsonConfigNodeName(FULL_XRAY_CONFIG, 'full')).assertEqual('Custom full config');
      expect(resolveJsonConfigNodeName('{"type":"policy-group","name":"PG","outbounds":[]}', 'policy-group')).assertEqual('PG');
      expect(resolveJsonConfigNodeName('{', 'full', 'Fallback')).assertEqual('Fallback');
      expect(defaultJsonConfigNodeName('full')).assertEqual('完整配置导入');
    });

    it('imports wireguard conf files as outbound json', 0, () => {
      const validation = normalizeOutboundInput(WIREGUARD_CONF);
      expect(validation.valid).assertTrue();
      expect(validation.protocol).assertEqual('wireguard');
      expect(validation.configType).assertEqual('outbound');
      expect(localizeCoreMessage('en', validation.message)).assertEqual('WireGuard config file imported successfully.');
      expect(validation.normalizedJson).assertContain('"secretKey": "private-key"');
      expect(validation.normalizedJson).assertContain('"address": [');
      expect(validation.normalizedJson).assertContain('"fd00::2/128"');
      expect(validation.normalizedJson).assertContain('"endpoint": "wg.example.com:51820"');
      expect(validation.normalizedJson).assertContain('"preSharedKey": "shared-key"');
      expect(validation.normalizedJson).assertContain('"reserved": [');

      const defaultReserved = normalizeOutboundInput(WIREGUARD_CONF_WITHOUT_RESERVED);
      expect(defaultReserved.valid).assertTrue();
      expect(defaultReserved.normalizedJson).assertContain('"reserved": [\n      0,\n      0,\n      0\n    ]');

      const defaultMtu = normalizeOutboundInput(WIREGUARD_CONF_WITHOUT_MTU);
      expect(defaultMtu.valid).assertTrue();
      expect(defaultMtu.normalizedJson).assertContain('"mtu": 1420');

      const missingEndpoint = normalizeOutboundInput('[Interface]\nPrivateKey = private-key\n[Peer]\nPublicKey = peer-key\n');
      expect(missingEndpoint.valid).assertFalse();
      expect(localizeCoreMessage('en', missingEndpoint.message)).assertEqual('WireGuard config is missing endpoint.');
    });

    it('applies app settings when generating xray config', 0, () => {
      const settings: AppSettings = {
        language: 'zh',
        uiModeNight: '0',
        speedEnabled: false,
        confirmRemove: false,
        startScanImmediate: false,
        startOnBoot: false,
        checkUpdatePreRelease: false,
        groupAllDisplay: false,
        doubleColumnDisplay: false,
        sniffingEnabled: true,
        routeOnlyEnabled: true,
        perAppProxyEnabled: false,
        perAppProxyList: [],
        perAppProxyBypass: false,
        localDnsEnabled: false,
        fakeDnsEnabled: false,
        appendHttpProxy: false,
        localSocksEnabled: false,
        localSocksPort: LOCAL_SOCKS_PROXY_PORT,
        localSocksDynamicPort: false,
        localSocksUdpEnabled: true,
        localSocksUsername: '',
        localSocksPassword: '',
        muxEnabled: true,
        muxConcurrency: 4,
        muxXudpConcurrency: 4,
        muxXudpQuic: 'reject',
        fragmentEnabled: false,
        fragmentPackets: 'tlshello',
        fragmentLength: '50-100',
        fragmentInterval: '10-20',
        ipv6Enabled: false,
        preferIpv6: false,
        proxySharingEnabled: false,
        allowInsecure: false,
        localDnsPort: 10853,
        vpnInterfaceAddressIndex: 0,
        vpnBypassLan: '1',
        vpnMtu: DEFAULT_VPN_MTU,
        vpnDns: '1.1.1.1',
        remoteDns: '9.9.9.9',
        domesticDns: '223.5.5.5',
        dnsHosts: '',
        delayTestUrl: DEFAULT_DELAY_TEST_URL,
        ipApiUrl: DEFAULT_IP_API_URL,
        realPingConcurrency: 16,
        logLevel: 'debug',
        outboundDomainResolveMethod: OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS,
        mode: 'VPN',
        trafficMode: 'rules',
        routingDomainStrategy: 'IPIfNonMatch',
        adBlockEnabled: false,
        routingRules: [],
        autoSortAfterTest: false,
        autoRemoveInvalidAfterTest: false
      };
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"loglevel": "debug"');
      expect(result.configJson).assertContain('"domainStrategy": "IPIfNonMatch"');
      expect(result.configJson).assertContain('"geosite:cn"');
      expect(result.configJson).assertContain('"sniffing"');
      expect(result.configJson).assertContain('"routeOnly": true');
      expect(result.configJson).assertContain('"mux"');
      expect(result.configJson).assertContain('"concurrency": -1');
      expect(result.configJson).assertContain('"9.9.9.9"');

      settings.logLevel = 'verbose';
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"loglevel": "warning"');
      expect(result.configJson.indexOf('"loglevel": "verbose"')).assertEqual(-1);

      settings.routingDomainStrategy = 'bad';
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"domainStrategy": "AsIs"');
      expect(result.configJson.indexOf('"domainStrategy": "bad"')).assertEqual(-1);
    });

    it('disables allowInsecure when a pinned certificate is configured like v2rayNG', 0, () => {
      const settings = buildSettingsFixture();
      const pinnedTlsOutbound =
        '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"pinned.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"pinned.example.com","allowInsecure":true,"pinnedPeerCertSha256":"test-pinned-ca256"}}}';
      const pinned = buildXrayConfigWithSettings(pinnedTlsOutbound, settings);
      expect(pinned.configJson).assertContain('"pinnedPeerCertSha256": "test-pinned-ca256"');
      expect(pinned.configJson).assertContain('"allowInsecure": false');

      const unpinnedTlsOutbound =
        '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"plain.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"plain.example.com","allowInsecure":true}}}';
      const unpinned = buildXrayConfigWithSettings(unpinnedTlsOutbound, settings);
      expect(unpinned.configJson).assertContain('"allowInsecure": true');
    });

    it('fills missing TLS serverName from transport or server domain like v2rayNG', 0, () => {
      const settings = buildSettingsFixture();
      const wsHostOutbound =
        '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"origin.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none"}]}]},"streamSettings":{"network":"ws","security":"tls","wsSettings":{"host":"cdn.example.com","path":"/ws"},"tlsSettings":{"allowInsecure":false}}}';
      const wsResult = buildXrayConfigWithSettings(wsHostOutbound, settings);
      expect(wsResult.configJson).assertContain('"serverName": "cdn.example.com"');

      const tcpIpHostOutbound =
        '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"server.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"tcp","security":"tls","tcpSettings":{"header":{"type":"http","request":{"headers":{"Host":["1.1.1.1"]},"path":["/"]}}},"tlsSettings":{"allowInsecure":false}}}';
      const fallbackResult = buildXrayConfigWithSettings(tcpIpHostOutbound, settings);
      expect(fallbackResult.configJson).assertContain('"serverName": "server.example.com"');
    });

    it('applies mux only to v2rayNG supported outbound protocols', 0, () => {
      const settings = buildSettingsFixture();
      settings.muxEnabled = true;
      settings.muxConcurrency = 6;
      settings.muxXudpConcurrency = 5;
      settings.muxXudpQuic = 'allow';

      const vmess = buildXrayConfigWithSettings(VMESS_TCP_OUTBOUND, settings);
      expect(vmess.configJson).assertContain('"mux"');
      expect(vmess.configJson).assertContain('"concurrency": 6');
      expect(vmess.configJson).assertContain('"xudpConcurrency": 5');
      expect(vmess.configJson).assertContain('"xudpProxyUDP443": "allow"');

      settings.muxConcurrency = -1;
      settings.muxXudpConcurrency = -1;
      settings.muxXudpQuic = 'skip';
      const muxDisabledByConcurrency = buildXrayConfigWithSettings(VMESS_TCP_OUTBOUND, settings);
      expect(muxDisabledByConcurrency.configJson).assertContain('"concurrency": -1');
      expect(muxDisabledByConcurrency.configJson).assertContain('"xudpConcurrency": -1');
      expect(muxDisabledByConcurrency.configJson).assertContain('"xudpProxyUDP443": "skip"');

      settings.muxXudpQuic = 'bad';
      const muxWithInvalidUdp443Policy = buildXrayConfigWithSettings(VMESS_TCP_OUTBOUND, settings);
      expect(muxWithInvalidUdp443Policy.configJson).assertContain('"xudpProxyUDP443": "reject"');
      expect(muxWithInvalidUdp443Policy.configJson.indexOf('"xudpProxyUDP443": "bad"')).assertEqual(-1);

      const trojan = buildXrayConfigWithSettings(TROJAN_OUTBOUND, settings);
      expect(trojan.configJson.indexOf('"mux"')).assertEqual(-1);

      const trojanWithMux =
        '{"protocol":"trojan","tag":"relay","settings":{"servers":[{"address":"relay.example.com","port":443,"password":"secret"}]},"mux":{"enabled":true,"concurrency":32,"xudpConcurrency":16,"xudpProxyUDP443":"allow"}}';
      const trojanImportedMux = buildXrayConfigWithSettings(trojanWithMux, settings);
      expect(trojanImportedMux.configJson).assertContain('"mux": {\n        "enabled": false,\n        "concurrency": -1');

      const xhttp = buildXrayConfigWithSettings(VLESS_XHTTP_OUTBOUND, settings);
      expect(xhttp.configJson.indexOf('"mux"')).assertEqual(-1);

      const wireguard = buildManualWireguardOutbound({
        tag: 'WG',
        host: 'wg.example.com',
        port: '51820',
        secretKey: 'private-key',
        publicKey: 'public-key',
        preSharedKey: '',
        localAddress: '',
        reserved: '',
        mtu: ''
      });
      expect(wireguard.success).assertTrue();
      const wgConfig = buildXrayConfigWithSettings(wireguard.outboundJson, settings);
      expect(wgConfig.configJson.indexOf('"mux"')).assertEqual(-1);

      const hysteria2 = buildManualHysteria2Outbound({
        tag: 'HY2',
        host: 'hy2.example.com',
        port: '443',
        password: 'secret',
        sni: '',
        alpn: '',
        allowInsecure: false,
        obfsPassword: '',
        portHopping: '',
        portHoppingInterval: '',
        pinSHA256: '',
        bandwidthDown: '',
        bandwidthUp: ''
      });
      expect(hysteria2.success).assertTrue();
      const hy2Config = buildXrayConfigWithSettings(hysteria2.outboundJson, settings);
      expect(hy2Config.configJson.indexOf('"mux"')).assertEqual(-1);

      settings.muxEnabled = false;
      const vmessWithMux =
        '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"vmess.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"vmess.example.com"}},"mux":{"enabled":true,"concurrency":32,"xudpConcurrency":16,"xudpProxyUDP443":"allow"}}';
      const disabledImportedMux = buildXrayConfigWithSettings(vmessWithMux, settings);
      expect(disabledImportedMux.configJson).assertContain('"mux": {\n        "enabled": false,\n        "concurrency": -1');
    });

    it('controls speed metrics with the speed display setting', 0, () => {
      const settings = buildSettingsFixture();
      const disabled = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(disabled.metricsServer === undefined).assertTrue();
      expect(disabled.configJson.indexOf('"metrics"') < 0).assertTrue();
      expect(disabled.configJson.indexOf('"stats"') < 0).assertTrue();
      expect(disabled.configJson.indexOf('"policy"') < 0).assertTrue();
      expect(disabled.configJson.indexOf('"tag": "metrics_in"') < 0).assertTrue();

      settings.speedEnabled = true;
      const enabled = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(enabled.metricsServer !== undefined).assertTrue();
      expect(enabled.configJson).assertContain('"metrics"');
      expect(enabled.configJson).assertContain('"stats"');
      expect(enabled.configJson).assertContain('"policy"');
      expect(enabled.configJson).assertContain('"tag": "metrics_in"');
    });

    it('applies local dns and fakedns settings to generated xray config', 0, () => {
      const settings = buildSettingsFixture();
      settings.localDnsEnabled = true;
      settings.fakeDnsEnabled = true;
      settings.sniffingEnabled = false;
      settings.dnsHosts = 'dns.google:8.8.8.8,cloudflare-dns.com:1.1.1.1';
      settings.routingRules = [
        {
          id: 'proxy-domain',
          remarks: 'Proxy domain',
          domain: ['domain:proxy.example'],
          ip: [],
          process: [],
          outboundTag: 'proxy',
          port: '',
          network: '',
          protocol: [],
          enabled: true,
          locked: false
        }
      ];
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"tag": "dns-out"');
      expect(result.configJson).assertContain('"protocol": "dns"');
      expect(result.configJson).assertContain('"port": "53"');
      expect(result.configJson).assertContain('"fakedns"');
      expect(result.configJson).assertContain('"dns.google": "8.8.8.8"');
      expect(result.configJson).assertContain('"cloudflare-dns.com": "1.1.1.1"');
      expect(result.configJson).assertContain('"geosite:cn"');
      expect(result.configJson).assertContain('"domain:proxy.example"');
      expect(result.configJson).assertContain('"destOverride"');

      settings.dnsHosts = '{"example.com":"127.0.0.1"}';
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"example.com": "127.0.0.1"');

      settings.localDnsEnabled = false;
      settings.fakeDnsEnabled = true;
      settings.sniffingEnabled = false;
      settings.dnsHosts = '';
      settings.routingRules = [];
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"sniffing": {\n        "enabled": true,\n        "destOverride": [\n          "fakedns"\n        ]\n      }');
      expect(result.configJson.indexOf('"tag": "dns-out"')).assertEqual(-1);
      expect(result.configJson.indexOf('"fakedns": [')).assertEqual(-1);
      expect(result.configJson.indexOf('"address": "fakedns"')).assertEqual(-1);
    });

    it('adds v2rayng style dns domain servers and dns routing rules', 0, () => {
      const settings = buildSettingsFixture();
      settings.remoteDns = '9.9.9.9,1.1.1.1';
      settings.domesticDns = '223.5.5.5,119.29.29.29';
      settings.routingRules = [
        {
          id: 'proxy-dns-domain',
          remarks: 'Proxy DNS domain',
          domain: ['domain:proxy.example'],
          ip: [],
          process: [],
          outboundTag: 'proxy',
          port: '',
          network: '',
          protocol: [],
          enabled: true,
          locked: false
        },
        {
          id: 'direct-dns-domain',
          remarks: 'Direct DNS domain',
          domain: ['domain:direct.example', 'geosite:cn'],
          ip: [],
          process: [],
          outboundTag: 'direct',
          port: '',
          network: '',
          protocol: [],
          enabled: true,
          locked: false
        },
        {
          id: 'blocked-dns-domain',
          remarks: 'Blocked DNS domain',
          domain: ['domain:blocked.example'],
          ip: [],
          process: [],
          outboundTag: 'block',
          port: '',
          network: '',
          protocol: [],
          enabled: true,
          locked: false
        }
      ];

      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"tag": "dns"');
      expect(result.configJson).assertContain('"enableParallelQuery": true');
      expect(result.configJson).assertContain('"address": "9.9.9.9"');
      expect(result.configJson).assertContain('"domain:proxy.example"');
      expect(result.configJson).assertContain('"tag": "domestic-dns-0"');
      expect(result.configJson).assertContain('"domain:direct.example"');
      expect(result.configJson).assertContain('"tag": "domestic-dns-0_cn_expect"');
      expect(result.configJson).assertContain('"expectIPs"');
      expect(result.configJson).assertContain('"geoip:cn"');
      expect(result.configJson).assertContain('"domain:blocked.example": "127.0.0.1"');
      expect(hasInboundOutboundRule(result.configJson, 'dns', 'proxy')).assertTrue();
      expect(hasInboundOutboundRule(result.configJson, 'domestic-dns-0', 'direct')).assertTrue();
    });

    it('adds v2rayng default dns hosts before user hosts', 0, () => {
      const settings = buildSettingsFixture();
      settings.dnsHosts = 'dns.google:8.8.4.4';

      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      const config = JSON.parse(result.configJson) as Record<string, Object>;
      const dns = config.dns as Record<string, Object>;
      const hosts = dns.hosts as Record<string, Object>;
      const aliDns = hosts['dns.alidns.com'] as Array<string>;
      const cloudflareDns = hosts['one.one.one.one'] as Array<string>;

      expect(hosts['domain:googleapis.cn'] as string).assertEqual('googleapis.com');
      expect(aliDns[0]).assertEqual('223.5.5.5');
      expect(aliDns[3]).assertEqual('2400:3200:baba::1');
      expect(cloudflareDns[0]).assertEqual('1.1.1.1');
      expect(cloudflareDns[2]).assertEqual('2606:4700:4700::1111');
      expect(hosts['dns.google'] as string).assertEqual('8.8.4.4');
    });

    it('applies outbound domain pre-resolve settings to generated xray config', 0, () => {
      const settings = buildSettingsFixture();
      settings.dnsHosts = 'example.com:203.0.113.8';
      settings.outboundDomainResolveMethod = OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS;
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"example.com": "203.0.113.8"');
      expect(result.configJson).assertContain('"domainStrategy": "UseIP"');
      expect(result.configJson).assertContain('"happyEyeballs"');
      expect(result.configJson).assertContain('"prioritizeIPv6": false');
      expect(result.configJson).assertContain('"address": "example.com"');

      settings.outboundDomainResolveMethod = OUTBOUND_DOMAIN_RESOLVE_REPLACE;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"address": "203.0.113.8"');
      expect(result.configJson.indexOf('"address": "example.com"')).assertEqual(-1);

      settings.preferIpv6 = true;
      settings.dnsHosts = '{"example.com":["203.0.113.8","2001:db8::8"]}';
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"address": "2001:db8::8"');

      settings.outboundDomainResolveMethod = OUTBOUND_DOMAIN_RESOLVE_NONE;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"address": "example.com"');
    });

    it('merges live outbound domain pre-resolve results into runtime settings', 0, () => {
      const settings = buildSettingsFixture();
      settings.dnsHosts = '';
      settings.outboundDomainResolveMethod = OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS;
      let hosts = collectOutboundDomainPreResolveHosts(VLESS_REALITY_OUTBOUND, settings);
      expect(hosts.length).assertEqual(1);
      expect(hosts[0]).assertEqual('example.com');

      hosts = collectOutboundDomainPreResolveHosts(PROXY_CHAIN_CONFIG, settings, 'proxy-chain');
      expect(hosts.length).assertEqual(2);
      expect(hosts[0]).assertEqual('example.com');
      expect(hosts[1]).assertEqual('relay.example.com');

      const fullHosts = collectOutboundDomainPreResolveHosts(FULL_XRAY_CONFIG, settings, 'full');
      expect(fullHosts.length).assertEqual(0);

      const runtimeSettings = withOutboundDomainResolvedHosts(settings, {
        'example.com': ['203.0.113.9', '2001:db8::9', '203.0.113.9']
      }) as AppSettings;
      expect(settings.dnsHosts).assertEqual('');
      expect(runtimeSettings.dnsHosts).assertContain('example.com');
      expect(runtimeSettings.dnsHosts).assertContain('203.0.113.9');
      expect(runtimeSettings.dnsHosts).assertContain('2001:db8::9');
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, runtimeSettings);
      expect(result.configJson).assertContain('"domainStrategy": "UseIP"');
      expect(result.configJson).assertContain('"address": "example.com"');

      settings.dnsHosts = 'example.com:203.0.113.8';
      hosts = collectOutboundDomainPreResolveHosts(VLESS_REALITY_OUTBOUND, settings);
      expect(hosts.length).assertEqual(0);

      settings.dnsHosts = '';
      settings.outboundDomainResolveMethod = OUTBOUND_DOMAIN_RESOLVE_REPLACE;
      const replaceSettings = withOutboundDomainResolvedHosts(settings, {
        'example.com': ['203.0.113.10']
      }) as AppSettings;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, replaceSettings);
      expect(result.configJson).assertContain('"address": "203.0.113.10"');
      expect(result.configJson.indexOf('"address": "example.com"')).assertEqual(-1);
    });

    it('applies vpn mtu to generated tun inbound', 0, () => {
      expect(DEFAULT_VPN_MTU).assertEqual(1500);
      const defaultResult = buildXrayConfig(VLESS_REALITY_OUTBOUND);
      expect(defaultResult.configJson).assertContain('"mtu": 1500');
      const settings = buildSettingsFixture();
      settings.vpnMtu = 1420;
      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"settings"');
      expect(result.configJson).assertContain('"mtu": 1420');
    });

    it('applies enabled custom routing rules to generated xray config', 0, () => {
      const settings = buildSettingsFixture();
      settings.routeOnlyEnabled = true;
      settings.adBlockEnabled = true;
      settings.routingRules = [
        {
          id: 'rule-direct',
          remarks: 'Direct example',
          domain: ['domain:example.com'],
          ip: ['geoip:private', 'geoip:cn', 'geoip:google'],
          process: [],
          outboundTag: 'direct',
          port: '443',
          network: 'tcp',
          protocol: ['tls'],
          enabled: true,
          locked: false
        },
        {
          id: 'rule-disabled',
          remarks: 'Disabled block',
          domain: ['domain:disabled.example'],
          ip: [],
          process: [],
          outboundTag: 'block',
          port: '',
          network: '',
          protocol: [],
          enabled: false,
          locked: false
        }
      ];

      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"domain:example.com"');
      expect(result.configJson).assertContain('"ext:geoip-only-cn-private.dat:private"');
      expect(result.configJson).assertContain('"ext:geoip-only-cn-private.dat:cn"');
      expect(result.configJson).assertContain('"geoip:google"');
      expect(result.configJson.indexOf('"geoip:private"')).assertEqual(-1);
      expect(result.configJson.indexOf('"geoip:cn"')).assertEqual(-1);
      expect(result.configJson).assertContain('"port": "443"');
      expect(result.configJson).assertContain('"network": "tcp"');
      expect(result.configJson).assertContain('"tls"');
      expect(result.configJson).assertContain('"geosite:category-ads-all"');
      expect(result.configJson).assertContain('"geosite:cn"');
      expect(result.configJson.indexOf('domain:disabled.example')).assertEqual(-1);
      const adRuleIndex = findRoutingRuleIndexByDomain(result.configJson, 'geosite:category-ads-all');
      const customRuleIndex = findRoutingRuleIndexByDomain(result.configJson, 'domain:example.com');
      const cnRuleIndex = findRoutingRuleIndexByDomain(result.configJson, 'geosite:cn');
      expect(adRuleIndex >= 0).assertTrue();
      expect(customRuleIndex > adRuleIndex).assertTrue();
      expect(cnRuleIndex > customRuleIndex).assertTrue();
    });

    it('gates process routing rules behind route only mode', 0, () => {
      const settings = buildSettingsFixture();
      settings.routeOnlyEnabled = false;
      settings.routingRules = [
        {
          id: 'mixed-process-rule',
          remarks: 'Mixed process rule',
          domain: ['domain:app.example'],
          ip: [],
          process: ['com.example.app', UNIDENTIFIED_PROCESS_PACKAGE],
          outboundTag: 'direct',
          port: '',
          network: '',
          protocol: [],
          enabled: true,
          locked: false
        },
        {
          id: 'process-only-rule',
          remarks: 'Process only rule',
          domain: [],
          ip: [],
          process: [UNIDENTIFIED_PROCESS_PACKAGE],
          outboundTag: 'block',
          port: '',
          network: '',
          protocol: [],
          enabled: true,
          locked: false
        }
      ];

      const disabled = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(disabled.configJson).assertContain('"domain:app.example"');
      expect(disabled.configJson.indexOf('"process"')).assertEqual(-1);
      expect(disabled.configJson.indexOf('com.example.app')).assertEqual(-1);
      expect(disabled.configJson.indexOf('"-1"')).assertEqual(-1);
      expect(disabled.configJson.indexOf('"routeOnly"')).assertEqual(-1);

      settings.routeOnlyEnabled = true;
      const enabled = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(enabled.configJson).assertContain('"routeOnly": true');
      expect(enabled.configJson).assertContain('"process": [');
      expect(enabled.configJson).assertContain('"-1"');
      expect(enabled.configJson.indexOf('com.example.app')).assertEqual(-1);

      const resolvedProcesses = normalizeRoutingRuleProcesses(
        ['com.example.app', 'com.missing.app', UNIDENTIFIED_PROCESS_PACKAGE],
        (packageName: string): string | undefined => packageName === 'com.example.app' ? '10123' : undefined
      );
      expect(resolvedProcesses.length).assertEqual(2);
      expect(resolvedProcesses[0]).assertEqual('10123');
      expect(resolvedProcesses[1]).assertEqual('-1');
    });

    it('keeps route only sniffing when protocol sniffing is disabled', 0, () => {
      const settings = buildSettingsFixture();
      settings.sniffingEnabled = false;
      settings.localDnsEnabled = false;
      settings.fakeDnsEnabled = false;
      settings.routeOnlyEnabled = true;

      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"sniffing": {\n        "enabled": false,\n        "destOverride": [],\n        "routeOnly": true\n      }');
    });

    it('appends local http proxy inbound when enabled', 0, () => {
      const settings = buildSettingsFixture();
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson.indexOf('"tag": "http-in"')).assertEqual(-1);

      settings.appendHttpProxy = true;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson.indexOf('"tag": "http-in"')).assertEqual(-1);
      expect(result.httpProxyPort === undefined).assertTrue();

      settings.localSocksEnabled = true;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"tag": "http-in"');
      expect(result.configJson).assertContain('"listen": "127.0.0.1"');
      expect(result.configJson).assertContain('"protocol": "http"');
      expect(LOCAL_HTTP_PROXY_PORT).assertEqual(10809);
      expect(result.configJson).assertContain(`"port": ${LOCAL_HTTP_PROXY_PORT}`);
      expect(result.configJson).assertContain('"inboundTag"');
      expect(result.configJson).assertContain('"outboundTag": "proxy"');
      expect(result.httpProxyPort).assertEqual(LOCAL_HTTP_PROXY_PORT);

      settings.proxySharingEnabled = true;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain(`"listen": "${LOCAL_HTTP_PROXY_LAN_HOST}"`);
      expect(result.httpProxyHost).assertEqual(LOCAL_HTTP_PROXY_LAN_HOST);
    });

    it('appends local socks proxy inbound with auth settings', 0, () => {
      const settings = buildSettingsFixture();
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson.indexOf('"tag": "socks-in"')).assertEqual(-1);

      settings.localSocksEnabled = true;
      settings.localSocksPort = 10818;
      settings.localSocksUdpEnabled = false;
      settings.localSocksUsername = 'user';
      settings.localSocksPassword = 'pass';
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.socksPort).assertEqual(10818);
      expect(result.configJson).assertContain('"tag": "socks-in"');
      expect(result.configJson).assertContain('"protocol": "socks"');
      expect(result.configJson).assertContain('"auth": "password"');
      expect(result.configJson).assertContain('"udp": false');
      expect(result.configJson).assertContain('"user": "user"');
      expect(result.configJson).assertContain('"pass": "pass"');
      expect(result.configJson).assertContain('"outboundTag": "proxy"');

      settings.proxySharingEnabled = true;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.socksHost).assertEqual(LOCAL_HTTP_PROXY_LAN_HOST);
      expect(result.configJson).assertContain(`"listen": "${LOCAL_HTTP_PROXY_LAN_HOST}"`);
    });

    it('enables local socks proxy by default like v2rayNG', 0, () => {
      expect(DEFAULT_APP_SETTINGS.localSocksEnabled).assertTrue();
      expect(DEFAULT_APP_SETTINGS.localSocksPort).assertEqual(10808);
      expect(LOCAL_SOCKS_PROXY_PORT).assertEqual(10808);
      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, DEFAULT_APP_SETTINGS);
      expect(result.configJson).assertContain('"tag": "socks-in"');
      expect(result.configJson).assertContain('"protocol": "socks"');
      expect(result.configJson).assertContain('"port": 10808');
      expect(result.configJson).assertContain('"auth": "noauth"');
      expect(result.configJson).assertContain('"udp": true');
      expect(result.socksPort).assertEqual(LOCAL_SOCKS_PROXY_PORT);
    });

    it('builds proxy only runtime without tun and with local socks inbound', 0, () => {
      const settings = buildSettingsFixture();
      settings.mode = APP_MODE_PROXY_ONLY;
      settings.localSocksEnabled = false;
      settings.appendHttpProxy = false;
      settings.localDnsEnabled = true;
      settings.fakeDnsEnabled = true;
      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson.indexOf('"tag": "tun-in"')).assertEqual(-1);
      expect(result.configJson.indexOf('"protocol": "tun"')).assertEqual(-1);
      expect(result.configJson).assertContain('"tag": "socks-in"');
      expect(result.configJson).assertContain('"protocol": "socks"');
      expect(result.configJson.indexOf('"tag": "dns-out"')).assertEqual(-1);
      expect(result.socksPort).assertEqual(LOCAL_SOCKS_PROXY_PORT);
    });

    it('routes proxy only policy groups through local proxy inbounds', 0, () => {
      const settings = buildSettingsFixture();
      settings.mode = APP_MODE_PROXY_ONLY;
      settings.localSocksEnabled = true;
      settings.appendHttpProxy = true;
      const result = buildRuntimeXrayConfig(POLICY_GROUP_CONFIG, settings, 'policy-group');
      expect(result.configJson.indexOf('"tag": "tun-in"')).assertEqual(-1);
      expect(result.configJson).assertContain('"tag": "socks-in"');
      expect(result.configJson).assertContain('"tag": "http-in"');
      expect(result.configJson).assertContain('"balancerTag": "balancer"');
      expect(hasInboundBalancerRule(result.configJson, 'http-in', 'balancer')).assertTrue();
      expect(result.configJson).assertContain('"socks-in"');
    });

    it('selects runtime local socks dynamic port safely', 0, () => {
      const settings = buildSettingsFixture();
      settings.localSocksEnabled = true;
      settings.localSocksDynamicPort = true;
      settings.localSocksPort = 10818;
      expect(shouldUseDynamicLocalSocksPort(settings)).assertTrue();
      expect(selectRuntimeLocalSocksPort(settings, [19080])).assertEqual(19080);
      expect(selectRuntimeLocalSocksPort(settings, [LOCAL_HTTP_PROXY_PORT, 19080], [LOCAL_HTTP_PROXY_PORT])).assertEqual(19080);
      expect(selectRuntimeLocalSocksPort(settings, [0, 70000])).assertEqual(10818);
      expect(selectRuntimeLocalSocksPort(settings, [LOCAL_HTTP_PROXY_PORT], [LOCAL_HTTP_PROXY_PORT])).assertEqual(10818);

      const runtimeSettings = withRuntimeLocalSocksPort(settings, 19081);
      expect(runtimeSettings.localSocksPort).assertEqual(19081);
      expect(settings.localSocksPort).assertEqual(10818);

      settings.localSocksDynamicPort = false;
      expect(shouldUseDynamicLocalSocksPort(settings)).assertFalse();
      expect(selectRuntimeLocalSocksPort(settings, [19082])).assertEqual(10818);

      settings.mode = APP_MODE_PROXY_ONLY;
      settings.localSocksDynamicPort = true;
      settings.localSocksEnabled = false;
      expect(shouldUseDynamicLocalSocksPort(settings)).assertTrue();
      expect(selectRuntimeLocalSocksPort(settings, [19083])).assertEqual(19083);
    });

    it('uses requested socks port for delay test config', 0, () => {
      const customPort = 19081;
      const result = buildDelayTestConfig(VLESS_REALITY_OUTBOUND, customPort);
      expect(result.configJson).assertContain('"tag":"socks-in"');
      expect(result.configJson).assertContain(`"port":${customPort}`);
      expect(result.configJson.indexOf(`"port":${DELAY_TEST_SOCKS_PORT}`)).assertEqual(-1);
    });

    it('removes outbound mux from delay test config like v2rayNG speedtest', 0, () => {
      const vmessWithMux =
        '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"vmess.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"vmess.example.com"}},"mux":{"enabled":true,"concurrency":32,"xudpConcurrency":16,"xudpProxyUDP443":"allow"}}';
      const result = buildDelayTestConfig(vmessWithMux, 19082);
      expect(result.configJson.indexOf('"mux"')).assertEqual(-1);
      expect(result.configJson).assertContain('"tag":"socks-in"');
      expect(result.configJson).assertContain('"tag":"proxy"');
    });

    it('applies hysteria2 bandwidth and masks to runtime finalmask', 0, () => {
      const hysteria2 = buildManualHysteria2Outbound({
        tag: 'HY2',
        host: 'hy2.example.com',
        port: '443',
        password: 'secret',
        sni: 'cdn.example.com',
        alpn: 'h3',
        allowInsecure: true,
        obfsPassword: 'obfs-secret',
        portHopping: '20000-50000',
        portHoppingInterval: '10-60',
        pinSHA256: 'hy2-pinned-sha256',
        bandwidthDown: '100 mbps',
        bandwidthUp: '20 mbps'
      });
      expect(hysteria2.success).assertTrue();

      const result = buildXrayConfigWithSettings(hysteria2.outboundJson, buildSettingsFixture());
      expect(result.configJson).assertContain('"protocol": "hysteria"');
      expect(result.configJson.indexOf('"protocol": "hysteria2"')).assertEqual(-1);
      expect(result.configJson).assertContain('"address": "hy2.example.com"');
      expect(result.configJson).assertContain('"port": 443');
      expect(result.configJson).assertContain('"version": 2');
      expect(result.configJson).assertContain('"network": "hysteria"');
      expect(result.configJson).assertContain('"hysteriaSettings"');
      expect(result.configJson).assertContain('"auth": "secret"');
      expect(result.configJson).assertContain('"security": "tls"');
      expect(result.configJson).assertContain('"serverName": "cdn.example.com"');
      expect(result.configJson).assertContain('"alpn"');
      expect(result.configJson).assertContain('"h3"');
      expect(result.configJson).assertContain('"allowInsecure": false');
      expect(result.configJson).assertContain('"pinnedPeerCertSha256": "hy2-pinned-sha256"');
      expect(result.configJson).assertContain('"finalmask"');
      expect(result.configJson).assertContain('"congestion": "brutal"');
      expect(result.configJson).assertContain('"brutalUp": "20 mbps"');
      expect(result.configJson).assertContain('"brutalDown": "100 mbps"');
      expect(result.configJson).assertContain('"udpHop"');
      expect(result.configJson).assertContain('"ports": "20000-50000"');
      expect(result.configJson).assertContain('"interval": "10-60"');
      expect(result.configJson).assertContain('"type": "salamander"');
      expect(result.configJson).assertContain('"password": "obfs-secret"');

      const defaultSni = buildManualHysteria2Outbound({
        tag: 'HY2',
        host: 'fallback.hy2.example.com',
        port: '443',
        password: 'secret',
        sni: '',
        alpn: '',
        allowInsecure: false,
        obfsPassword: '',
        portHopping: '',
        portHoppingInterval: '',
        pinSHA256: '',
        bandwidthDown: '',
        bandwidthUp: ''
      });
      expect(defaultSni.success).assertTrue();
      const defaultSniResult = buildXrayConfigWithSettings(defaultSni.outboundJson, buildSettingsFixture());
      expect(defaultSniResult.configJson).assertContain('"serverName": "fallback.hy2.example.com"');

      const importedNoAlpnHy2 =
        '{"protocol":"hysteria2","tag":"hy2-import","settings":{"servers":[{"address":"no-alpn.hy2.example.com","port":443,"password":"secret"}]}}';
      const noAlpnResult = buildXrayConfigWithSettings(importedNoAlpnHy2, buildSettingsFixture());
      expect(noAlpnResult.configJson).assertContain('"alpn"');
      expect(noAlpnResult.configJson).assertContain('"h3"');

      const importedInvalidAlpnHy2 =
        '{"protocol":"hysteria2","tag":"hy2-import","settings":{"servers":[{"address":"bad-alpn.hy2.example.com","port":443,"password":"secret","alpn":"bad"}]}}';
      const invalidAlpnResult = buildXrayConfigWithSettings(importedInvalidAlpnHy2, buildSettingsFixture());
      expect(invalidAlpnResult.configJson).assertContain('"alpn"');
      expect(invalidAlpnResult.configJson).assertContain('"h3"');
      expect(invalidAlpnResult.configJson.indexOf('"bad"')).assertEqual(-1);
    });

    it('applies prefer ipv6 to outbound happy eyeballs', 0, () => {
      const settings = buildSettingsFixture();
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson.indexOf('"happyEyeballs"')).assertEqual(-1);

      settings.preferIpv6 = true;
      settings.fragmentEnabled = true;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"domainStrategy": "UseIP"');
      expect(result.configJson).assertContain('"happyEyeballs"');
      expect(result.configJson).assertContain('"prioritizeIPv6": true');
      expect(result.configJson).assertContain('"interleave": 2');
      expect(result.configJson).assertContain('"finalmask"');
      expect(result.configJson).assertContain('"type": "fragment"');
      expect(result.configJson).assertContain('"packets": "1-3"');
      expect(result.configJson).assertContain('"type": "noise"');
      expect(result.configJson.indexOf('"fragment": {')).assertEqual(-1);
    });

    it('applies fragment finalmask like v2rayNG', 0, () => {
      const settings = buildSettingsFixture();
      settings.fragmentEnabled = true;
      settings.fragmentPackets = '1-2';
      settings.fragmentLength = '100-200';
      settings.fragmentInterval = '5-8';

      const tlsResult = buildXrayConfigWithSettings(VMESS_TCP_OUTBOUND, settings);
      expect(tlsResult.configJson).assertContain('"finalmask"');
      expect(tlsResult.configJson).assertContain('"type": "fragment"');
      expect(tlsResult.configJson).assertContain('"packets": "tlshello"');
      expect(tlsResult.configJson).assertContain('"length": "100-200"');
      expect(tlsResult.configJson).assertContain('"delay": "5-8"');
      expect(tlsResult.configJson).assertContain('"type": "noise"');
      expect(tlsResult.configJson).assertContain('"rand": "10-20"');
      expect(tlsResult.configJson.indexOf('"fragment": {')).assertEqual(-1);

      const preserved = buildXrayConfigWithSettings(VLESS_FINALMASK_OUTBOUND, settings);
      expect(preserved.configJson).assertContain('"type": "custom-fragment"');
      expect(preserved.configJson.indexOf('"packets"')).assertEqual(-1);
      expect(preserved.configJson.indexOf('"type": "noise"')).assertEqual(-1);

      const chain = buildRuntimeXrayConfig(PROXY_CHAIN_CONFIG, settings, 'proxy-chain');
      expect(chain.configJson).assertContain('"dialerProxy": "proxy-chain-1"');
      expect(chain.configJson.indexOf('"finalmask"')).assertEqual(-1);
    });

    it('keeps ipv6 routing separate from prefer ipv6', 0, () => {
      const settings = buildSettingsFixture();
      settings.preferIpv6 = true;
      const wireguard = buildManualWireguardOutbound({
        tag: 'WG',
        host: 'wg.example.com',
        port: '51820',
        secretKey: 'private-key',
        publicKey: 'public-key',
        preSharedKey: '',
        localAddress: '172.16.0.2/32, fd00::2/128',
        reserved: '',
        mtu: '1420'
      });
      expect(wireguard.success).assertTrue();

      let result = buildXrayConfigWithSettings(wireguard.outboundJson, settings);
      expect(result.configJson).assertContain('"happyEyeballs"');
      expect(result.configJson).assertContain('"172.16.0.2/32"');
      expect(result.configJson.indexOf('"fd00::2/128"')).assertEqual(-1);

      settings.ipv6Enabled = true;
      result = buildXrayConfigWithSettings(wireguard.outboundJson, settings);
      expect(result.configJson).assertContain('"fd00::2/128"');
    });

    it('imports routing presets while preserving locked rules', 0, () => {
      const lockedRule = buildRoutingRuleFixture('locked-rule', 'Locked keep', 'direct');
      lockedRule.locked = true;
      lockedRule.domain = ['domain:locked.example'];
      const unlockedRule = buildRoutingRuleFixture('unlocked-rule', 'Replace me', 'block');
      unlockedRule.domain = ['domain:replace.example'];

      const result = resetRoutingRulesFromPreset([unlockedRule, lockedRule], 'global');
      expect(result[0].id).assertEqual('locked-rule');
      expect(result[0].domain[0]).assertEqual('domain:locked.example');
      expect(result.length > 1).assertTrue();
      expect(result[1].id).assertContain('preset-global');
      expect(exportRoutingRulesJson(result)).assertContain('"locked": true');
    });

    it('keeps v2rayNG public DNS entries in routing presets', 0, () => {
      const chinaWhite = resetRoutingRulesFromPreset([], 'chinaWhite');
      const chinaWhiteJson = exportRoutingRulesJson(chinaWhite);
      expect(chinaWhite.length).assertEqual(8);
      expect(chinaWhiteJson).assertContain('"223.5.5.5"');
      expect(chinaWhiteJson).assertContain('"2400:3200::1"');
      expect(chinaWhiteJson).assertContain('"117.50.60.30"');
      expect(chinaWhiteJson).assertContain('"domain:alidns.com"');
      expect(chinaWhiteJson.indexOf('223.5.5.5') < chinaWhiteJson.indexOf('domain:alidns.com')).assertTrue();

      const chinaBlack = resetRoutingRulesFromPreset([], 'chinaBlack');
      const chinaBlackJson = exportRoutingRulesJson(chinaBlack);
      expect(chinaBlack.length).assertEqual(10);
      expect(chinaBlackJson).assertContain('"1.1.1.1"');
      expect(chinaBlackJson).assertContain('"2001:4860:4860::8888"');
      expect(chinaBlackJson).assertContain('"2a02:6b8::feed:a11"');
      expect(chinaBlackJson).assertContain('"domain:yandex.net"');
      expect(chinaBlackJson.indexOf('1.1.1.1') < chinaBlackJson.indexOf('domain:cloudflare-dns.com')).assertTrue();
    });

    it('imports routing rules json from clipboard format', 0, () => {
      const lockedRule = buildRoutingRuleFixture('locked-rule', 'Locked keep', 'direct');
      lockedRule.locked = true;
      const content = '[{"remarks":"Imported proxy","domain":["domain:import.example"],"outboundTag":"proxy"},{"remarks":"Ignored empty","outboundTag":"block"}]';
      const result = importRoutingRulesJson([lockedRule], content);

      expect(result.success).assertTrue();
      expect(result.count).assertEqual(1);
      expect(result.rules.length).assertEqual(2);
      expect(result.rules[0].id).assertEqual('locked-rule');
      expect(result.rules[1].remarks).assertEqual('Imported proxy');
      expect(result.rules[1].domain[0]).assertEqual('domain:import.example');
      expect(importRoutingRulesJson([], '{"bad":true}').success).assertFalse();
    });

    it('imports routing rules json from QR code payload format', 0, () => {
      const lockedRule = buildRoutingRuleFixture('locked-qr-rule', 'Locked keep', 'direct');
      lockedRule.locked = true;
      lockedRule.domain = ['domain:locked.example'];
      const content = '\n  [{"remarks":"QR proxy","domain":["domain:qr.example"],"outboundTag":"proxy"}]\n';
      const result = importRoutingRulesJson([lockedRule], content);

      expect(result.success).assertTrue();
      expect(result.count).assertEqual(1);
      expect(result.rules.length).assertEqual(2);
      expect(result.rules[0].id).assertEqual('locked-qr-rule');
      expect(result.rules[0].domain[0]).assertEqual('domain:locked.example');
      expect(result.rules[1].remarks).assertEqual('QR proxy');
      expect(result.rules[1].domain[0]).assertEqual('domain:qr.example');
    });

    it('preserves advanced outbound routing targets in rules json', 0, () => {
      const content = '[{"remarks":"Policy group target","domain":["domain:group.example"],"outboundTag":"policy-group"},{"remarks":"Proxy chain target","domain":["domain:chain.example"],"outboundTag":"proxy-chain"}]';
      const result = importRoutingRulesJson([], content);

      expect(result.success).assertTrue();
      expect(result.count).assertEqual(2);
      expect(result.rules[0].outboundTag).assertEqual('policy-group');
      expect(result.rules[1].outboundTag).assertEqual('proxy-chain');
      expect(exportRoutingRulesJson(result.rules)).assertContain('"outboundTag": "policy-group"');
      expect(exportRoutingRulesJson(result.rules)).assertContain('"outboundTag": "proxy-chain"');
    });

    it('routes policy-group custom rules to the current balancer target', 0, () => {
      const settings = buildSettingsFixture();
      settings.routingRules = [
        {
          id: 'policy-group-rule',
          remarks: 'Policy group route',
          domain: ['domain:group.example'],
          ip: [],
          process: [],
          outboundTag: 'policy-group',
          port: '',
          network: '',
          protocol: [],
          enabled: true,
          locked: false
        }
      ];

      const result = buildRuntimeXrayConfig(POLICY_GROUP_CONFIG, settings, 'policy-group');
      const config = JSON.parse(result.configJson) as Record<string, Object>;
      const routing = config.routing as Record<string, Object>;
      const rules = routing.rules as Array<Record<string, Object>>;
      let matchedRule = '';
      for (let index = 0; index < rules.length; index++) {
        const domains = rules[index].domain as Array<string>;
        if (Array.isArray(domains) && domains.indexOf('domain:group.example') >= 0) {
          matchedRule = JSON.stringify(rules[index]);
        }
      }

      expect(matchedRule).assertContain('"balancerTag":"balancer"');
      expect(matchedRule.indexOf('"outboundTag"')).assertEqual(-1);
    });

    it('has complete zh and en translations with fallback helpers', 0, () => {
      expect(missingTranslationKeys('zh').length).assertEqual(0);
      expect(missingTranslationKeys('en').length).assertEqual(0);
      expect(translate('zh', 'screen.settings.title')).assertEqual('设置');
      expect(translate('en', 'screen.settings.title')).assertEqual('Settings');
      expect(translate('en', 'settings.checkUpdatePreRelease')).assertEqual('Include pre-release versions');
      expect(translate('en', 'prompt.clipboardReadFailed')).assertEqual('Could not read clipboard');
      expect(translate('zh', 'prompt.pastedJsonConfig')).assertEqual('已粘贴 JSON 配置');
      expect(translate('zh', 'missing.translation.key')).assertEqual('missing.translation.key');
      expect(formatTranslation('en', 'subscription.updateComplete', ['count'], ['3'])).assertContain('3');
      expect(formatOne('zh', 'subscription.updateComplete', 'count', '3')).assertContain('3');
      expect(localizedProfileSavedText('en', 0)).assertEqual('Not saved');
      expect(localizeCoreMessage('en', '请先粘贴 Xray outbound JSON。')).assertEqual('Paste Xray outbound JSON first.');
      const unsupportedShare = parseShareLinkToOutboundJson('ftp://example.com/node');
      expect(unsupportedShare.success).assertFalse();
      expect(unsupportedShare.message).assertEqual(buildUnsupportedShareLinkMessage());
      expect(unsupportedShare.message).assertContain('socks4://');
      expect(unsupportedShare.message).assertContain('https://');
      expect(unsupportedShare.message).assertContain('hy2://');
      expect(localizeCoreMessage('en', unsupportedShare.message)).assertContain('socks5://');
      expect(localizeCoreMessage('en', unsupportedShare.message)).assertContain('hy2://');
      for (let index = 0; index < SUPPORTED_SHARE_LINK_SCHEMES.length; index++) {
        expect(isSupportedShareLink(`${SUPPORTED_SHARE_LINK_SCHEMES[index]}example`)).assertTrue();
      }
      expect(normalizeLanguage('auto')).assertEqual('auto');
      expect(normalizeLanguage('en')).assertEqual('en');
      expect(normalizeLanguage('en-US')).assertEqual('en');
      expect(normalizeLanguage('zh')).assertEqual('zh');
      expect(normalizeLanguage('zh-Hans')).assertEqual('zh');
      expect(normalizeLanguage('fr')).assertEqual('auto');
      expect(resolveSystemLanguage('en-US')).assertEqual('en');
      expect(resolveSystemLanguage('zh-Hans')).assertEqual('zh');
      expect(resolveSystemLanguage('fr-FR')).assertEqual('zh');
      expect(resolveLanguage('auto', 'en-US')).assertEqual('en');
      expect(resolveLanguage('auto', 'zh-Hans')).assertEqual('zh');
      expect(resolveLanguage('fr', 'en-US')).assertEqual('en');
    });

    it('formats geo asset count status', 0, () => {
      const geosite = geoDataSpecForFile('geosite.dat');
      const geoip = geoDataSpecForFile('geoip.dat');
      const geoipOnlyCnPrivate = geoDataSpecForFile(GEOIP_ONLY_CN_PRIVATE_FILE_NAME);
      expect(BUILTIN_GEO_DATA_FILE_NAMES.length).assertEqual(3);
      expect(BUILTIN_GEO_DATA_FILE_NAMES[2]).assertEqual(GEOIP_ONLY_CN_PRIVATE_FILE_NAME);
      expect(geosite?.name).assertEqual('geosite');
      expect(geosite?.geoType).assertEqual('domain');
      expect(geoip?.name).assertEqual('geoip');
      expect(geoip?.geoType).assertEqual('ip');
      expect(geoipOnlyCnPrivate?.name).assertEqual('geoip-only-cn-private');
      expect(geoipOnlyCnPrivate?.geoType).assertEqual('ip');
      expect(geoDataSpecForFile('custom.dat') === null).assertTrue();
      expect(buildBuiltinGeoAssetUrl('https://example.com/release/', 'geosite.dat')).assertEqual('https://example.com/release/geosite.dat');
      expect(buildBuiltinGeoAssetUrl('https://example.com/release', 'geoip.dat')).assertEqual('https://example.com/release/geoip.dat');
      expect(buildBuiltinGeoAssetUrl('https://example.com/release/', GEOIP_ONLY_CN_PRIVATE_FILE_NAME)).assertEqual(GEOIP_ONLY_CN_PRIVATE_URL);
      expect(V2RAYNG_GEO_FILE_SOURCE_REPOS.length).assertEqual(3);
      expect(GEO_FILE_SOURCES.length >= V2RAYNG_GEO_FILE_SOURCE_REPOS.length).assertTrue();
      expect(GEO_FILE_SOURCES[0].name).assertEqual('Loyalsoldier/v2ray-rules-dat');
      expect(GEO_FILE_SOURCES[1].name).assertEqual('runetfreedom/russia-v2ray-rules-dat');
      expect(GEO_FILE_SOURCES[1].url).assertEqual('https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/');
      expect(GEO_FILE_SOURCES[2].name).assertEqual('Chocolate4U/Iran-v2ray-rules');
      expect(buildBuiltinGeoAssetUrl(GEO_FILE_SOURCES[2].url, 'geosite.dat')).assertEqual('https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download/geosite.dat');

      const count = parseGeoCountData('{"categoryCount":2,"ruleCount":345,"codes":[{"code":"cn","ruleCount":100}]}');
      expect(count?.categoryCount).assertEqual(2);
      expect(count?.ruleCount).assertEqual(345);
      expect(parseGeoCountData('{"bad":true}') === null).assertTrue();
      if (count !== null) {
        expect(formatGeoCountSummary('zh', count)).assertEqual('2 类 / 345 条规则');
        expect(formatGeoCountSummary('en', count)).assertEqual('2 categories / 345 rules');
      }
      expect(formatGeoCountUnavailable('en', 'CGoCountGeoData not exported')).assertContain('CGoCountGeoData not exported');
    });

    it('normalizes scanned asset URL payloads for QR import', 0, () => {
      const result = normalizeScannedAssetUrl(' https://example.com/geosite.dat?download=1 ');
      expect(result.valid).assertTrue();
      expect(result.name).assertEqual('geosite');
      expect(result.url).assertEqual('https://example.com/geosite.dat?download=1');

      const root = normalizeScannedAssetUrl('https://example.com/');
      expect(root.valid).assertTrue();
      expect(root.name).assertEqual('asset');

      const unsafeName = normalizeScannedAssetUrl('https://example.com/custom:rules?.dat');
      expect(unsafeName.valid).assertTrue();
      expect(unsafeName.name).assertEqual('custom_rules');

      expect(normalizeScannedAssetUrl('ftp://example.com/geosite.dat').valid).assertFalse();
    });

    it('detects duplicate custom asset names like v2rayNG asset remarks', 0, () => {
      const assets: Array<AssetNameEntry> = [
        { id: 'asset-a', name: 'geosite' },
        { id: 'asset-b', name: 'geoip' }
      ];
      expect(hasDuplicateAssetName(assets, 'geosite')).assertTrue();
      expect(hasDuplicateAssetName(assets, ' geosite ')).assertTrue();
      expect(hasDuplicateAssetName(assets, 'geosite', 'asset-a')).assertFalse();
      expect(hasDuplicateAssetName(assets, 'geoip', 'asset-a')).assertTrue();
      expect(hasDuplicateAssetName(assets, '')).assertFalse();
    });

    it('hides local file asset editing like v2rayNG', 0, () => {
      expect(isEditableCustomAssetUrl('file')).assertFalse();
      expect(isEditableCustomAssetUrl(' file ')).assertFalse();
      expect(isEditableCustomAssetUrl('local://import')).assertFalse();
      expect(isEditableCustomAssetUrl('https://example.com/geosite.dat')).assertTrue();
      expect(isEditableCustomAssetUrl('http://example.com/geoip.dat')).assertTrue();
    });

    it('round-trips vpn settings through settings draft', 0, () => {
      const settings = buildSettingsFixture();
      settings.ipv6Enabled = true;
      settings.preferIpv6 = true;
      settings.localDnsPort = 1053;
      settings.localSocksEnabled = true;
      settings.appendHttpProxy = true;
      settings.localSocksPort = 10818;
      settings.localSocksDynamicPort = true;
      settings.localSocksUdpEnabled = false;
      settings.localSocksUsername = 'socks-user';
      settings.localSocksPassword = 'socks-pass';
      settings.vpnInterfaceAddressIndex = 5;
      settings.vpnBypassLan = '2';
      settings.vpnMtu = 1420;
      settings.muxEnabled = true;
      settings.muxConcurrency = 16;
      settings.muxXudpConcurrency = 12;
      settings.muxXudpQuic = 'allow';
      settings.fragmentEnabled = true;
      settings.fragmentPackets = '1-2';
      settings.fragmentLength = '100-200';
      settings.fragmentInterval = '5-8';
      settings.logLevel = 'error';
      settings.dnsHosts = 'dns.google:8.8.8.8,cloudflare-dns.com:1.1.1.1';
      settings.ipApiUrl = 'https://ip.example/geoip';
      settings.realPingConcurrency = 32;
      settings.outboundDomainResolveMethod = OUTBOUND_DOMAIN_RESOLVE_REPLACE;
      settings.mode = APP_MODE_PROXY_ONLY;
      settings.routingDomainStrategy = 'IPOnDemand';
      settings.uiModeNight = '2';
      settings.speedEnabled = true;
      settings.confirmRemove = true;
      settings.startScanImmediate = true;
      settings.startOnBoot = true;
      settings.checkUpdatePreRelease = true;
      settings.groupAllDisplay = true;
      settings.doubleColumnDisplay = true;
      const draft = SETTINGS_CONTROLLER.toDraft(settings);
      expect(draft.uiModeNight).assertEqual('2');
      expect(draft.speedEnabled).assertTrue();
      expect(draft.confirmRemove).assertTrue();
      expect(draft.startScanImmediate).assertTrue();
      expect(draft.startOnBoot).assertTrue();
      expect(draft.checkUpdatePreRelease).assertTrue();
      expect(draft.groupAllDisplay).assertTrue();
      expect(draft.doubleColumnDisplay).assertTrue();
      expect(draft.ipv6Enabled).assertTrue();
      expect(draft.preferIpv6).assertTrue();
      expect(draft.localDnsPort).assertEqual('1053');
      expect(draft.localSocksEnabled).assertTrue();
      expect(draft.appendHttpProxy).assertTrue();
      expect(draft.localSocksPort).assertEqual('10818');
      expect(draft.localSocksDynamicPort).assertTrue();
      expect(draft.localSocksUdpEnabled).assertFalse();
      expect(draft.localSocksUsername).assertEqual('socks-user');
      expect(draft.localSocksPassword).assertEqual('socks-pass');
      expect(draft.vpnInterfaceAddressIndex).assertEqual(5);
      expect(draft.vpnBypassLan).assertEqual('2');
      expect(draft.vpnMtu).assertEqual('1420');
      expect(draft.muxEnabled).assertTrue();
      expect(draft.muxConcurrency).assertEqual('16');
      expect(draft.muxXudpConcurrency).assertEqual('12');
      expect(draft.muxXudpQuic).assertEqual('allow');
      expect(draft.fragmentEnabled).assertTrue();
      expect(draft.fragmentPackets).assertEqual('1-2');
      expect(draft.fragmentLength).assertEqual('100-200');
      expect(draft.fragmentInterval).assertEqual('5-8');
      expect(draft.logLevel).assertEqual('error');
      expect(draft.dnsHosts).assertEqual('dns.google:8.8.8.8,cloudflare-dns.com:1.1.1.1');
      expect(draft.ipApiUrl).assertEqual('https://ip.example/geoip');
      expect(draft.realPingConcurrency).assertEqual('32');
      expect(draft.outboundDomainResolveMethod).assertEqual(OUTBOUND_DOMAIN_RESOLVE_REPLACE);
      expect(draft.mode).assertEqual(APP_MODE_PROXY_ONLY);
      expect(draft.routingDomainStrategy).assertEqual('IPOnDemand');
      const rebuilt = SETTINGS_CONTROLLER.buildSettings(draft);
      expect(rebuilt.uiModeNight).assertEqual('2');
      expect(rebuilt.speedEnabled).assertTrue();
      expect(rebuilt.confirmRemove).assertTrue();
      expect(rebuilt.startScanImmediate).assertTrue();
      expect(rebuilt.startOnBoot).assertTrue();
      expect(rebuilt.checkUpdatePreRelease).assertTrue();
      expect(rebuilt.groupAllDisplay).assertTrue();
      expect(rebuilt.doubleColumnDisplay).assertTrue();
      expect(rebuilt.ipv6Enabled).assertTrue();
      expect(rebuilt.preferIpv6).assertTrue();
      expect(rebuilt.localDnsPort).assertEqual(1053);
      expect(rebuilt.localSocksEnabled).assertTrue();
      expect(rebuilt.appendHttpProxy).assertTrue();
      expect(rebuilt.localSocksPort).assertEqual(10818);
      expect(rebuilt.localSocksDynamicPort).assertTrue();
      expect(rebuilt.localSocksUdpEnabled).assertFalse();
      expect(rebuilt.localSocksUsername).assertEqual('socks-user');
      expect(rebuilt.localSocksPassword).assertEqual('socks-pass');
      expect(rebuilt.vpnInterfaceAddressIndex).assertEqual(5);
      expect(rebuilt.vpnBypassLan).assertEqual('2');
      expect(rebuilt.vpnMtu).assertEqual(1420);
      expect(rebuilt.muxEnabled).assertTrue();
      expect(rebuilt.muxConcurrency).assertEqual(16);
      expect(rebuilt.muxXudpConcurrency).assertEqual(12);
      expect(rebuilt.muxXudpQuic).assertEqual('allow');
      expect(rebuilt.fragmentEnabled).assertTrue();
      expect(rebuilt.fragmentPackets).assertEqual('1-2');
      expect(rebuilt.fragmentLength).assertEqual('100-200');
      expect(rebuilt.fragmentInterval).assertEqual('5-8');
      expect(rebuilt.logLevel).assertEqual('error');
      expect(rebuilt.dnsHosts).assertEqual('dns.google:8.8.8.8,cloudflare-dns.com:1.1.1.1');
      expect(rebuilt.ipApiUrl).assertEqual('https://ip.example/geoip');
      expect(rebuilt.realPingConcurrency).assertEqual(32);
      expect(rebuilt.outboundDomainResolveMethod).assertEqual(OUTBOUND_DOMAIN_RESOLVE_REPLACE);
      expect(rebuilt.mode).assertEqual(APP_MODE_PROXY_ONLY);
      expect(rebuilt.routingDomainStrategy).assertEqual('IPOnDemand');

      draft.vpnInterfaceAddressIndex = 99;
      expect(SETTINGS_CONTROLLER.buildSettings(draft).vpnInterfaceAddressIndex).assertEqual(0);
      draft.vpnBypassLan = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).vpnBypassLan).assertEqual('1');
      draft.localDnsPort = '70000';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).localDnsPort).assertEqual(10853);
      draft.localSocksPort = '70000';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).localSocksPort).assertEqual(LOCAL_SOCKS_PROXY_PORT);
      draft.vpnMtu = '1279';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).vpnMtu).assertEqual(1280);
      draft.vpnMtu = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).vpnMtu).assertEqual(DEFAULT_VPN_MTU);
      draft.vpnMtu = '';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).vpnMtu).assertEqual(DEFAULT_VPN_MTU);
      draft.muxConcurrency = '-1';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxConcurrency).assertEqual(-1);
      draft.muxConcurrency = '0';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxConcurrency).assertEqual(0);
      draft.muxConcurrency = '-2';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxConcurrency).assertEqual(8);
      draft.muxXudpConcurrency = '-1';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpConcurrency).assertEqual(-1);
      draft.muxXudpConcurrency = '0';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpConcurrency).assertEqual(0);
      draft.muxXudpConcurrency = '1025';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpConcurrency).assertEqual(8);
      draft.muxXudpConcurrency = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpConcurrency).assertEqual(8);
      draft.muxXudpQuic = 'skip';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpQuic).assertEqual('skip');
      draft.muxXudpQuic = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpQuic).assertEqual('reject');
      draft.fragmentPackets = '';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).fragmentPackets).assertEqual('tlshello');
      draft.fragmentPackets = '1-5';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).fragmentPackets).assertEqual('1-5');
      draft.fragmentPackets = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).fragmentPackets).assertEqual('tlshello');
      draft.logLevel = 'none';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).logLevel).assertEqual('none');
      draft.logLevel = 'verbose';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).logLevel).assertEqual('warning');
      draft.outboundDomainResolveMethod = 'bad' as OutboundDomainResolveMethod;
      expect(SETTINGS_CONTROLLER.buildSettings(draft).outboundDomainResolveMethod).assertEqual(OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS);
      draft.routingDomainStrategy = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).routingDomainStrategy).assertEqual('AsIs');
      draft.dnsHosts = '  ';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).dnsHosts).assertEqual('');
      draft.realPingConcurrency = '0';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).realPingConcurrency).assertEqual(1);
      draft.realPingConcurrency = '256';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).realPingConcurrency).assertEqual(128);
      draft.realPingConcurrency = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).realPingConcurrency).assertEqual(16);
      draft.uiModeNight = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).uiModeNight).assertEqual('0');
      draft.localSocksEnabled = false;
      draft.appendHttpProxy = true;
      expect(SETTINGS_CONTROLLER.buildSettings(draft).appendHttpProxy).assertFalse();
    });

    it('normalizes real ping concurrency like v2rayNG', 0, () => {
      expect(normalizeRealPingConcurrency(undefined)).assertEqual(16);
      expect(normalizeRealPingConcurrency(0)).assertEqual(1);
      expect(normalizeRealPingConcurrency(5.8)).assertEqual(5);
      expect(normalizeRealPingConcurrency(256)).assertEqual(128);
      expect(normalizeRoutingDomainStrategy(undefined)).assertEqual('AsIs');
      expect(normalizeRoutingDomainStrategy('IPIfNonMatch')).assertEqual('IPIfNonMatch');
      expect(normalizeRoutingDomainStrategy('IPOnDemand')).assertEqual('IPOnDemand');
      expect(normalizeRoutingDomainStrategy('bad')).assertEqual('AsIs');
      expect(resolveDelayTestUrl(undefined)).assertEqual(DEFAULT_DELAY_TEST_URL);
      expect(resolveDelayTestUrl('')).assertEqual(DEFAULT_DELAY_TEST_URL);
      expect(resolveDelayTestUrl('  https://probe.example/ping  ')).assertEqual('https://probe.example/ping');
    });

    it('handles v2rayng style per-app package list actions', 0, () => {
      const selfPackage = 'com.lmlm.hey';
      const normalized = normalizePerAppPackageList([
        ' com.google.android.youtube ',
        'com.google.android.youtube',
        selfPackage,
        'invalid',
        'com.huawei.hbrowser'
      ], selfPackage);
      expect(normalized.length).assertEqual(2);
      expect(normalized[0]).assertEqual('com.google.android.youtube');
      expect(normalized[1]).assertEqual('com.huawei.hbrowser');

      const selected = selectAllPerAppPackages(['com.tencent.mm'], ['com.google.android.youtube', selfPackage], selfPackage);
      expect(selected.length).assertEqual(2);
      expect(selected[0]).assertEqual('com.tencent.mm');
      expect(selected[1]).assertEqual('com.google.android.youtube');

      const inverted = invertVisiblePerAppPackages(
        ['com.tencent.mm', 'com.huawei.hbrowser'],
        ['com.tencent.mm', 'com.google.android.youtube'],
        selfPackage
      );
      expect(inverted.length).assertEqual(2);
      expect(inverted[0]).assertEqual('com.huawei.hbrowser');
      expect(inverted[1]).assertEqual('com.google.android.youtube');

      const cleared = clearVisiblePerAppPackages(
        ['com.tencent.mm', 'com.huawei.hbrowser'],
        ['com.tencent.mm'],
        selfPackage
      );
      expect(cleared.length).assertEqual(1);
      expect(cleared[0]).assertEqual('com.huawei.hbrowser');

      const exported = exportPerAppProxyList(false, ['com.tencent.mm', 'com.tencent.mm', selfPackage], selfPackage);
      expect(exported).assertEqual('false\ncom.tencent.mm');

      const imported = importPerAppProxyList('true\ncom.google.android.youtube\ncom.tencent.mm, com.tencent.mm\ncom.lmlm.hey', false, selfPackage);
      expect(imported.success).assertTrue();
      expect(imported.bypass).assertTrue();
      expect(imported.count).assertEqual(2);
      expect(imported.packages[0]).assertEqual('com.google.android.youtube');
      expect(imported.packages[1]).assertEqual('com.tencent.mm');

      const packageOnlyImport = importPerAppProxyList('com.huawei.hbrowser', true, selfPackage);
      expect(packageOnlyImport.success).assertTrue();
      expect(packageOnlyImport.bypass).assertTrue();
      expect(packageOnlyImport.packages[0]).assertEqual('com.huawei.hbrowser');

      const autoProxy = selectAutoProxyPackages([
        'com.huawei.hbrowser',
        'com.tencent.mm',
        'com.google.android.youtube',
        'com.google.android.webview',
        selfPackage
      ], false, 'com.huawei.hbrowser', selfPackage);
      expect(autoProxy.length).assertEqual(2);
      expect(autoProxy[0]).assertEqual('com.huawei.hbrowser');
      expect(autoProxy[1]).assertEqual('com.google.android.youtube');

      const autoBypass = selectAutoProxyPackages([
        'com.huawei.hbrowser',
        'com.tencent.mm',
        'com.google.android.youtube',
        'com.google.android.webview'
      ], true, 'com.huawei.hbrowser', selfPackage);
      expect(autoBypass.length).assertEqual(2);
      expect(autoBypass[0]).assertEqual('com.tencent.mm');
      expect(autoBypass[1]).assertEqual('com.google.android.webview');

      expect(ANDROID_PACKAGE_NAME_LIST_URL).assertEqual('https://raw.githubusercontent.com/2dust/androidpackagenamelist/master/proxy.txt');
      const remoteContent = resolveAutoProxyPackageListContent('com.custom.browser\n');
      const remoteAutoProxy = selectAutoProxyPackages([
        'com.custom.browser',
        'com.huawei.hbrowser',
        'com.google.android.webview'
      ], false, remoteContent, selfPackage, false);
      expect(remoteAutoProxy.length).assertEqual(1);
      expect(remoteAutoProxy[0]).assertEqual('com.custom.browser');
      expect(resolveAutoProxyPackageListContent('').indexOf('com.openai.chatgpt') >= 0).assertTrue();
    });

    it('maps per-app vpn package lists like v2rayNG', 0, () => {
      const disabled = createDefaultVpnConfig(false, false, []);
      const disabledBlocked = disabled.blockedApplications ?? [];
      expect(disabledBlocked[0]).assertEqual(BUNDLE_NAME);

      const enabledEmpty = createDefaultVpnConfig(true, false, []);
      const emptyBlocked = enabledEmpty.blockedApplications ?? [];
      expect(emptyBlocked[0]).assertEqual(BUNDLE_NAME);

      const selfOnly = createDefaultVpnConfig(true, false, [BUNDLE_NAME]);
      const selfOnlyBlocked = selfOnly.blockedApplications ?? [];
      expect(selfOnlyBlocked[0]).assertEqual(BUNDLE_NAME);
      expect(selfOnly.trustedApplications === undefined).assertTrue();

      const proxySelected = createDefaultVpnConfig(true, false, [BUNDLE_NAME, 'com.tencent.mm']);
      const trusted = proxySelected.trustedApplications ?? [];
      expect(trusted.length).assertEqual(1);
      expect(trusted[0]).assertEqual('com.tencent.mm');
      expect(proxySelected.blockedApplications === undefined).assertTrue();

      const bypassSelected = createDefaultVpnConfig(true, true, [BUNDLE_NAME, 'com.tencent.mm']);
      const blocked = bypassSelected.blockedApplications ?? [];
      expect(blocked.length).assertEqual(2);
      expect(blocked[0]).assertEqual(BUNDLE_NAME);
      expect(blocked[1]).assertEqual('com.tencent.mm');
    });

    it('normalizes ui mode night like v2rayNG', 0, () => {
      expect(normalizeUiModeNight(undefined)).assertEqual('0');
      expect(normalizeUiModeNight('0')).assertEqual('0');
      expect(normalizeUiModeNight('1')).assertEqual('1');
      expect(normalizeUiModeNight('2')).assertEqual('2');
      expect(normalizeUiModeNight('bad')).assertEqual('0');
      expect(normalizeUiModeNight('bad', '2')).assertEqual('2');
    });

    it('normalizes runtime mode like v2rayNG pref_mode', 0, () => {
      expect(normalizeAppRuntimeMode(undefined)).assertEqual(APP_MODE_VPN);
      expect(normalizeAppRuntimeMode(APP_MODE_VPN)).assertEqual(APP_MODE_VPN);
      expect(normalizeAppRuntimeMode(APP_MODE_PROXY_ONLY)).assertEqual(APP_MODE_PROXY_ONLY);
      expect(normalizeAppRuntimeMode('bad')).assertEqual(APP_MODE_VPN);
    });

    it('parses current connection IP API responses like v2rayNG', 0, () => {
      const ipSb = parseRemoteIpInfoContent('{"ip":"203.0.113.8","country_code":"US"}');
      expect(ipSb.ok).assertTrue();
      expect(ipSb.summary).assertEqual('(US) 203.0.113.8');

      const alt = parseRemoteIpInfoContent('{"query":"198.51.100.9","location":{"country_code":"JP"}}');
      expect(alt.ok).assertTrue();
      expect(alt.summary).assertEqual('(JP) 198.51.100.9');

      expect(parseRemoteIpInfoContent('{').ok).assertFalse();
      expect(normalizeIpApiUrl('')).assertEqual(DEFAULT_IP_API_URL);
      expect(normalizeIpApiUrl('ftp://example.com')).assertEqual('');
    });

    it('formats runtime values through shared helpers', 0, () => {
      expect(formatBytes(512)).assertEqual('512 B');
      expect(formatBytes(2048)).assertEqual('2.0 KB');
      expect(formatDuration(65)).assertEqual('01:05');
    });

    it('builds throttled speed notification copy from runtime stats', 0, () => {
      const stats: RuntimeStats = {
        uploadBytes: 3048,
        downloadBytes: 6096,
        xrayRunning: true,
        tunRunning: true,
        lastMessage: ''
      };
      const previous = sampleSpeedNotificationStats({
        uploadBytes: 1000,
        downloadBytes: 2000,
        xrayRunning: true,
        tunRunning: true,
        lastMessage: ''
      }, 1000);
      const current = sampleSpeedNotificationStats(stats, 3000);
      const rates = calculateSpeedNotificationRates(previous, current);
      expect(rates.uploadBytesPerSecond).assertEqual(1024);
      expect(rates.downloadBytesPerSecond).assertEqual(2048);
      expect(buildSpeedNotificationText('en', rates)).assertEqual('Upload 1.0 KB/s | Download 2.0 KB/s');
      expect(buildSpeedNotificationAdditionalText('en', stats, '00:02')).assertEqual('Duration 00:02 | Total 3.0 KB / 6.0 KB');
      expect(shouldPublishSpeedNotification(1000, 0, false)).assertTrue();
      expect(shouldPublishSpeedNotification(2000, 1000, true)).assertFalse();
      expect(shouldPublishSpeedNotification(4000, 1000, true)).assertTrue();
    });

    it('builds system text share wants', 0, () => {
      const want = buildTextShareWant('Hey nodes', '  vless://example  ');
      const entities = want.entities === undefined ? [] : want.entities;
      expect(want.action).assertEqual('ohos.want.action.sendData');
      expect(want.type).assertEqual('text/plain');
      expect(entities.join('|')).assertEqual('entity.system.default');
      expect(want.parameters?.['ohos.extra.param.key.contentTitle']?.toString()).assertEqual('Hey nodes');
      expect(want.parameters?.['ohos.extra.param.key.shareAbstract']?.toString()).assertEqual('vless://example');
      expect(want.parameters?.['ohos.extra.param.key.shareUrl']?.toString()).assertEqual('vless://example');

      const subscriptionWant = buildTextShareWant('Sub A', '  https://sub.example/list  ');
      expect(subscriptionWant.parameters?.['ohos.extra.param.key.contentTitle']?.toString()).assertEqual('Sub A');
      expect(subscriptionWant.parameters?.['ohos.extra.param.key.shareAbstract']?.toString()).assertEqual('https://sub.example/list');
      expect(subscriptionWant.parameters?.['ohos.extra.param.key.shareUrl']?.toString()).assertEqual('https://sub.example/list');
    });

    it('filters and formats logcat entries like v2rayNG log actions', 0, () => {
      const items = [
        '09-01 10:00:00.000 I/HeyVpn: started',
        '09-01 10:00:01.000 E/AndroidRuntime: crash',
        '09-01 10:00:02.000 I/GoLog: outbound ready'
      ];
      expect(filterLogItems(items, '').length).assertEqual(3);
      expect(filterLogItems(items, 'AndroidRuntime')[0]).assertContain('crash');
      expect(filterLogItems(items, 'missing').length).assertEqual(0);
      expect(formatLogcatText(filterLogItems(items, 'I/'))).assertEqual(
        '09-01 10:00:00.000 I/HeyVpn: started\n09-01 10:00:02.000 I/GoLog: outbound ready'
      );
    });

    it('builds and validates app backup payloads', 0, () => {
      const backup = buildAppBackupPayload('profile-json', 'settings-json', 'subscription-json', 'assets-json', 1234);
      expect(backup).assertContain('"hey_backup":true');
      const parsed = parseAppBackupPayload(backup);
      expect(parsed.valid).assertTrue();
      expect(parsed.payload?.version).assertEqual('1');
      expect(parsed.payload?.createdAt).assertEqual(1234);
      expect(parsed.payload?.profile).assertEqual('profile-json');
      expect(parsed.payload?.settings).assertEqual('settings-json');
      expect(parsed.payload?.subscription).assertEqual('subscription-json');
      expect(parsed.payload?.assets).assertEqual('assets-json');
      expect(parseAppBackupPayload('{"hey_backup":false}').valid).assertFalse();
      expect(parseAppBackupPayload('{').valid).assertFalse();
    });

    it('wraps app backup payloads in restorable zip packages', 0, () => {
      const backup = buildAppBackupPayload('profile-json', 'settings-json', 'subscription-json', 'assets-json', 1234);
      const zip = buildAppBackupZipFromPayload(backup);
      const view = new Uint8Array(zip);
      expect(view[0]).assertEqual(0x50);
      expect(view[1]).assertEqual(0x4B);
      expect(view[2]).assertEqual(0x03);
      expect(view[3]).assertEqual(0x04);

      const parsed = parseAppBackupData(zip);
      expect(parsed.valid).assertTrue();
      expect(parsed.payload?.profile).assertEqual('profile-json');
      expect(parsed.payload?.settings).assertEqual('settings-json');
      expect(parseAppBackupData(backup).valid).assertTrue();
    });

    it('normalizes webdav backup urls and auth headers', 0, () => {
      const config = normalizeWebDavConfig({
        baseUrl: 'https://example.com/remote.php/dav/files/user/',
        username: 'alice',
        password: 'secret',
        remoteBasePath: '/backups/hey/',
        remoteFileName: 'backup.json',
        timeoutSeconds: 2
      });
      expect(config.baseUrl).assertEqual('https://example.com/remote.php/dav/files/user');
      expect(config.remoteBasePath).assertEqual('backups/hey');
      expect(config.timeoutSeconds).assertEqual(5);
      expect(buildWebDavRemoteUrl(config)).assertEqual('https://example.com/remote.php/dav/files/user/backups/hey/backup.json');
      expect(buildWebDavAuthorizationHeader(config.username, config.password)).assertEqual('Basic YWxpY2U6c2VjcmV0');

      const mkcolUrls = buildWebDavMkcolUrls(config);
      expect(mkcolUrls[0]).assertEqual('https://example.com/remote.php');
      expect(mkcolUrls[mkcolUrls.length - 1]).assertEqual('https://example.com/remote.php/dav/files/user/backups/hey');
      expect(validateWebDavConfig({ baseUrl: 'ftp://example.com' }).valid).assertFalse();
      expect(validateWebDavConfig({ baseUrl: 'https://example.com/dav', remoteFileName: 'bad/name.json' }).valid).assertFalse();
      expect(isWebDavMkcolAcceptedStatus(201)).assertTrue();
      expect(isWebDavMkcolAcceptedStatus(405)).assertTrue();
      expect(isWebDavMkcolAcceptedStatus(500)).assertFalse();
      expect(DEFAULT_WEBDAV_BACKUP_FILE_NAME).assertEqual('backup_ng.zip');
      expect(normalizeWebDavConfig({}).remoteFileName).assertEqual('backup_ng.zip');
    });

    it('filters nodes by name protocol and source', 0, () => {
      const nodes = buildNodeFixture();
      expect(filterNodes(nodes, 'alpha').length).assertEqual(1);
      expect(filterNodes(nodes, 'trojan').length).assertEqual(1);
      expect(filterNodes(nodes, 'manual').length).assertEqual(1);
    });

    it('sorts nodes by delay name and protocol', 0, () => {
      const nodes = buildNodeFixture();
      expect(sortNodes(nodes, 'delay')[0].name).assertEqual('Alpha');
      expect(sortNodes(nodes, 'name')[0].name).assertEqual('Alpha');
      expect(sortNodes(nodes, 'protocol')[0].protocol).assertEqual('trojan');
    });

    it('dedupes nodes by raw link and normalized outbound json', 0, () => {
      const nodes = buildNodeFixture();
      const duplicateRaw: ProxyNode = copyNode(nodes[0], 'raw-duplicate');
      duplicateRaw.rawLink = nodes[0].rawLink;
      const duplicateJson: ProxyNode = copyNode(nodes[2], 'json-duplicate');
      duplicateJson.rawLink = '';
      duplicateJson.outboundJson = nodes[2].outboundJson;
      const result = dedupeNodes(nodes.concat([duplicateRaw, duplicateJson]));
      expect(result.length).assertEqual(nodes.length);
    });

    it('applies v2rayNG visible batch operations across all groups', 0, () => {
      const nodes = buildNodeFixture();
      const duplicateAlpha = copyNode(nodes[2], 'node-alpha-duplicate');
      duplicateAlpha.rawLink = nodes[2].rawLink;
      const failedTwo = copyNode(nodes[0], 'node-failed-two');
      failedTwo.rawLink = 'trojan://secret2@example.com:443#failed-two';
      failedTwo.delayStatus = 'timeout';
      const groups = [
        buildGroupFixture('sub-a', 'A', [nodes[2], nodes[0]], nodes[2].id),
        buildGroupFixture('sub-b', 'B', [duplicateAlpha, nodes[1], failedTwo], duplicateAlpha.id)
      ];

      const deduped = dedupeVisibleNodesInGroups(groups, [nodes[2], duplicateAlpha], 100);
      expect(deduped.removedCount).assertEqual(1);
      expect(deduped.groups[1].nodes[0].id).assertEqual(nodes[1].id);
      expect(deduped.groups[1].updatedAt).assertEqual(100);

      const failedRemoved = removeVisibleTestFailedNodesFromGroups(groups, [nodes[0], nodes[1], failedTwo], 101);
      expect(failedRemoved.removedCount).assertEqual(2);
      expect(failedRemoved.groups[0].nodes.length).assertEqual(1);
      expect(failedRemoved.groups[1].nodes.length).assertEqual(2);

      const cleared = removeVisibleNodesFromGroups(groups, [nodes[2], failedTwo], 102);
      expect(cleared.removedCount).assertEqual(2);
      expect(cleared.groups[0].nodes[0].id).assertEqual(nodes[0].id);
      expect(cleared.groups[1].nodes.length).assertEqual(2);
    });

    it('applies v2rayNG post delay-test remove and sort by subscription group', 0, () => {
      const nodes = buildNodeFixture();
      const slow = copyNode(nodes[2], 'node-slow');
      slow.name = 'Slow';
      slow.delayMs = 900;
      slow.rawLink = 'vless://slow@example.com:443#slow';
      const fast = copyNode(nodes[2], 'node-fast');
      fast.name = 'Fast';
      fast.delayMs = 80;
      fast.rawLink = 'vless://fast@example.com:443#fast';
      const failed = copyNode(nodes[0], 'node-failed-sort');
      failed.name = 'Failed';
      failed.delayStatus = 'failed';
      const pending = copyNode(nodes[1], 'node-pending-sort');
      pending.name = 'Pending';
      const groups = [
        buildGroupFixture('sub-a', 'A', [slow, failed, fast], failed.id),
        buildGroupFixture('sub-b', 'B', [pending], pending.id)
      ];

      const result = applyDelayTestPostActionsToGroups(groups, [failed], [slow, failed, fast, pending], true, true, 200);
      expect(result.removedCount).assertEqual(1);
      expect(result.sortedGroupCount).assertEqual(2);
      expect(result.groups[0].nodes.length).assertEqual(2);
      expect(result.groups[0].nodes[0].id).assertEqual(fast.id);
      expect(result.groups[0].nodes[1].id).assertEqual(slow.id);
      expect(result.groups[0].selectedNodeId).assertEqual(slow.id);
      expect(result.groups[0].updatedAt).assertEqual(200);
    });

    it('sorts by test results with v2rayNG subscription group semantics', 0, () => {
      const nodes = buildNodeFixture();
      const untested = copyNode(nodes[1], 'node-untested-manual-sort');
      untested.name = 'Untested';
      untested.delayMs = 0;
      const slow = copyNode(nodes[2], 'node-slow-manual-sort');
      slow.name = 'Slow';
      slow.delayMs = 900;
      const failed = copyNode(nodes[0], 'node-failed-manual-sort');
      failed.name = 'Failed';
      failed.delayMs = -1;
      failed.delayStatus = 'timeout';
      const fast = copyNode(nodes[2], 'node-fast-manual-sort');
      fast.name = 'Fast';
      fast.delayMs = 80;
      const otherSlow = copyNode(nodes[2], 'node-other-slow-manual-sort');
      otherSlow.name = 'Other Slow';
      otherSlow.delayMs = 600;
      const otherFast = copyNode(nodes[2], 'node-other-fast-manual-sort');
      otherFast.name = 'Other Fast';
      otherFast.delayMs = 50;
      const groups = [
        buildGroupFixture('sub-a', 'A', [untested, slow, failed, fast], failed.id),
        buildGroupFixture('sub-b', 'B', [otherSlow, otherFast], otherSlow.id)
      ];

      const activeGroupResult = sortGroupsByDelayTargets(groups, [slow, fast], 300);
      expect(activeGroupResult.sortedGroupCount).assertEqual(1);
      expect(activeGroupResult.groups[0].nodes[0].id).assertEqual(fast.id);
      expect(activeGroupResult.groups[0].nodes[1].id).assertEqual(slow.id);
      expect(activeGroupResult.groups[0].nodes[2].id).assertEqual(untested.id);
      expect(activeGroupResult.groups[0].nodes[3].id).assertEqual(failed.id);
      expect(activeGroupResult.groups[0].selectedNodeId).assertEqual(failed.id);
      expect(activeGroupResult.groups[0].updatedAt).assertEqual(300);
      expect(activeGroupResult.groups[1].nodes[0].id).assertEqual(otherSlow.id);

      const allGroupsResult = sortGroupsByDelayTargets(groups, [slow, fast, otherSlow, otherFast], 301);
      expect(allGroupsResult.sortedGroupCount).assertEqual(2);
      expect(allGroupsResult.groups[1].nodes[0].id).assertEqual(otherFast.id);
      expect(allGroupsResult.groups[1].nodes[1].id).assertEqual(otherSlow.id);
    });

    it('finds invalid nodes and exports only v2rayNG shareable nodes', 0, () => {
      const nodes = buildNodeFixture();
      const invalid = copyNode(nodes[0], 'invalid');
      invalid.rawLink = '';
      invalid.outboundJson = '{';
      const fullConfigNode = copyNode(nodes[2], 'full-config');
      fullConfigNode.name = 'Full config';
      fullConfigNode.protocol = 'custom';
      fullConfigNode.rawLink = '';
      fullConfigNode.outboundJson = FULL_XRAY_CONFIG;
      fullConfigNode.configType = 'full';
      expect(findInvalidNodes(nodes.concat([invalid, fullConfigNode])).length).assertEqual(1);

      const proxyChainNode = copyNode(nodes[2], 'proxy-chain-config');
      proxyChainNode.name = 'Proxy chain';
      proxyChainNode.protocol = 'proxy-chain';
      proxyChainNode.rawLink = '';
      proxyChainNode.outboundJson = PROXY_CHAIN_CONFIG;
      proxyChainNode.configType = 'proxy-chain';
      const policyGroupNode = copyNode(nodes[2], 'policy-group-config');
      policyGroupNode.name = 'Policy group';
      policyGroupNode.protocol = 'policy-group';
      policyGroupNode.rawLink = '';
      policyGroupNode.outboundJson = POLICY_GROUP_CONFIG;
      policyGroupNode.configType = 'policy-group';

      const exportTargets = nodes.concat([invalid, fullConfigNode, proxyChainNode, policyGroupNode]);
      const exported = exportNodesText(exportTargets);
      expect(exported).assertContain('vless://');
      expect(exported).assertContain('trojan://secret@example.com:443#beta');
      expect(exported.indexOf('"protocol": "vless"')).assertEqual(-1);
      expect(exported.indexOf('"remarks": "Custom full config"')).assertEqual(-1);
      expect(exported.indexOf('chain-demo')).assertEqual(-1);
      expect(exported.indexOf('group-demo')).assertEqual(-1);
      const model = buildNodeExportModel('Nodes', exportTargets);
      expect(model.content).assertEqual(exported);
      expect(model.count).assertEqual(nodes.length);
    });

    it('builds v2rayNG-style full config content for node detail copy', 0, () => {
      const nodes = buildNodeFixture();
      const ordinary = buildNodeFullConfigModel(nodes[2], buildSettingsFixture());
      expect(ordinary.success).assertTrue();
      expect(ordinary.content).assertContain('"protocol": "tun"');
      expect(ordinary.content).assertContain('"protocol": "vless"');

      const fullConfigNode = copyNode(nodes[2], 'full-config-copy');
      fullConfigNode.protocol = 'custom';
      fullConfigNode.rawLink = '';
      fullConfigNode.configType = 'full';
      fullConfigNode.outboundJson = FULL_XRAY_CONFIG;
      const full = buildNodeFullConfigModel(fullConfigNode, buildSettingsFixture());
      expect(full.success).assertTrue();
      expect(full.content).assertContain('"remarks": "Custom full config"');
      expect(full.content).assertContain('"protocol": "freedom"');

      const sourceGroup = buildSubscriptionGroupFixture('sub-a', 'A');
      sourceGroup.nodes = buildAdvancedNodeFixture();
      const dynamic = buildPolicyGroupConfigFromSubscription('Latest Dynamic', 'leastPing', 'sub-a', 'trojan', [sourceGroup]);
      expect(dynamic.success).assertTrue();
      expect(dynamic.count).assertEqual(1);
      const dynamicNode = copyNode(nodes[2], 'dynamic-policy-copy');
      dynamicNode.protocol = 'policy-group';
      dynamicNode.rawLink = '';
      dynamicNode.configType = 'policy-group';
      dynamicNode.outboundJson = dynamic.configJson;
      const latestGroup = buildSubscriptionGroupFixture('sub-a', 'A');
      latestGroup.nodes = [buildAdvancedNodeFixture()[1]];
      const copied = buildNodeFullConfigModel(dynamicNode, buildSettingsFixture(), [latestGroup]);
      expect(copied.success).assertTrue();
      expect(copied.content).assertContain('"proxy-policy-group-1"');
      expect(copied.content).assertContain('"protocol": "trojan"');
      expect(copied.content.indexOf('"protocol": "vless"')).assertEqual(-1);

      const invalid = copyNode(nodes[2], 'invalid-full-copy');
      invalid.rawLink = '';
      invalid.outboundJson = '{';
      expect(buildNodeFullConfigModel(invalid, buildSettingsFixture()).success).assertFalse();
    });

    it('imports vless reality share link as outbound json', 0, () => {
      const link = 'vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&ech=test-ech-config&pcs=test-pinned-ca256&pbk=test-public-key&sid=abcd&spx=%2Fbot&pqv=test-mldsa65-verify&type=tcp#demo';
      const imported = parseShareLinkToOutboundJson(link);
      expect(imported.success).assertTrue();
      expect(imported.protocol).assertEqual('vless');
      expect(imported.outboundJson).assertContain('"protocol": "vless"');
      expect(imported.outboundJson).assertContain('"realitySettings"');
      expect(imported.outboundJson).assertContain('"echConfigList": "test-ech-config"');
      expect(imported.outboundJson).assertContain('"pinnedPeerCertSha256": "test-pinned-ca256"');
      expect(imported.outboundJson).assertContain('"publicKey": "test-public-key"');
      expect(imported.outboundJson).assertContain('"spiderX": "/bot"');
      expect(imported.outboundJson).assertContain('"mldsa65Verify": "test-mldsa65-verify"');
      const exported = formatOutboundJsonToShareLink(imported.outboundJson, 'demo');
      expect(exported).assertContain('ech=test-ech-config');
      expect(exported).assertContain('pcs=test-pinned-ca256');
      expect(exported).assertContain('pqv=test-mldsa65-verify');
      expect(exported).assertContain('headerType=none');

      const validation = normalizeOutboundInput(link);
      expect(validation.valid).assertTrue();
      expect(validation.normalizedJson).assertContain('"flow": "xtls-rprx-vision"');
      expect(validation.normalizedJson).assertContain('"mldsa65Verify": "test-mldsa65-verify"');
    });

    it('keeps v2rayNG flow, mux, loglevel, security, fragment, and transport options complete', 0, () => {
      expect(V2RAYNG_FLOW_OPTIONS.join('|')).assertEqual('none|xtls-rprx-vision|xtls-rprx-vision-udp443');
      expect(V2RAYNG_UTLS_FINGERPRINT_OPTIONS.join('|')).assertEqual('none|chrome|firefox|safari|ios|android|edge|360|qq|random|randomized');
      expect(V2RAYNG_DEFAULT_VMESS_SECURITY).assertEqual('chacha20-poly1305');
      expect(V2RAYNG_VMESS_SECURITY_OPTIONS.join('|')).assertEqual('chacha20-poly1305|aes-128-gcm|auto|none|zero');
      expect(V2RAYNG_SS_SECURITY_OPTIONS.join('|')).assertEqual('aes-256-gcm|aes-128-gcm|chacha20-poly1305|chacha20-ietf-poly1305|xchacha20-poly1305|xchacha20-ietf-poly1305|none|plain|2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305');
      expect(V2RAYNG_DEFAULT_MUX_XUDP_QUIC).assertEqual('reject');
      expect(V2RAYNG_MUX_XUDP_QUIC_OPTIONS.join('|')).assertEqual('reject|allow|skip');
      expect(normalizeV2rayNgMuxXudpQuic('bad')).assertEqual('reject');
      expect(V2RAYNG_DEFAULT_CORE_LOG_LEVEL).assertEqual('warning');
      expect(V2RAYNG_CORE_LOG_LEVEL_OPTIONS.join('|')).assertEqual('debug|info|warning|error|none');
      expect(normalizeV2rayNgCoreLogLevel('verbose')).assertEqual('warning');
      expect(V2RAYNG_DEFAULT_FRAGMENT_PACKETS).assertEqual('tlshello');
      expect(V2RAYNG_FRAGMENT_PACKET_OPTIONS.join('|')).assertEqual('tlshello|1-2|1-3|1-5');
      expect(normalizeV2rayNgFragmentPackets('bad')).assertEqual('tlshello');
      expect(V2RAYNG_SUPPORTED_TRANSPORT_OPTIONS.join('|')).assertEqual('tcp|kcp|ws|httpupgrade|xhttp|h2|grpc');
      expect(V2RAYNG_TCP_HEADER_TYPE_OPTIONS.join('|')).assertEqual('none|http');
      expect(V2RAYNG_KCP_HEADER_TYPE_OPTIONS.join('|')).assertEqual('none|srtp|utp|wechat-video|dtls|wireguard|dns');
      expect(V2RAYNG_XHTTP_MODE_OPTIONS.join('|')).assertEqual('auto|packet-up|stream-up|stream-one');
      expect(V2RAYNG_GRPC_MODE_OPTIONS.join('|')).assertEqual('gun|multi');
      expect(V2RAYNG_DEFAULT_STREAM_ALPN).assertEqual('');
      expect(V2RAYNG_STREAM_ALPN_OPTIONS.join('|')).assertEqual('|h3|h2|http/1.1|h3,h2,http/1.1|h3,h2|h2,http/1.1');
      expect(normalizeV2rayNgStreamAlpn('h3,h2')).assertEqual('h3,h2');
      expect(normalizeV2rayNgStreamAlpn('bad')).assertEqual('');
      expect(normalizeV2rayNgStreamAlpnWithFallback('', 'h3')).assertEqual('h3');
      expect(normalizeV2rayNgStreamAlpnWithFallback('bad', 'h3')).assertEqual('h3');

      const link = 'vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&flow=xtls-rprx-vision-udp443&security=reality&sni=www.example.com&fp=randomized&pbk=test-public-key&sid=abcd&type=tcp#udp443';
      const imported = parseShareLinkToOutboundJson(link);
      expect(imported.success).assertTrue();
      expect(imported.outboundJson).assertContain('"flow": "xtls-rprx-vision-udp443"');
      expect(imported.outboundJson).assertContain('"fingerprint": "randomized"');
      const exported = formatOutboundJsonToShareLink(imported.outboundJson, 'udp443');
      expect(exported).assertContain('flow=xtls-rprx-vision-udp443');
      expect(exported).assertContain('fp=randomized');
    });

    it('round-trips tcp http header transport parameters', 0, () => {
      const tcp = parseShareLinkToOutboundJson('vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&security=tls&type=tcp&headerType=http&host=front.example%2Capi.example&path=%2Flogin%2C%2Fapi#tcp-http');
      expect(tcp.success).assertTrue();
      expect(tcp.outboundJson).assertContain('"network": "tcp"');
      expect(tcp.outboundJson).assertContain('"tcpSettings"');
      expect(tcp.outboundJson).assertContain('"type": "http"');
      expect(tcp.outboundJson).assertContain('"Host"');
      expect(tcp.outboundJson).assertContain('"front.example"');
      expect(tcp.outboundJson).assertContain('"/login"');
      const exportedTcp = formatOutboundJsonToShareLink(tcp.outboundJson, 'tcp-http');
      expect(exportedTcp).assertContain('type=tcp');
      expect(exportedTcp).assertContain('headerType=http');
      expect(exportedTcp).assertContain('host=front.example%2Capi.example');
      expect(exportedTcp).assertContain('path=%2Flogin%2C%2Fapi');
    });

    it('exports bare url-style outbounds with v2rayNG tcp defaults', 0, () => {
      const bareVlessJson = '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"plain.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none"}]}]}}';
      const exportedVless = formatOutboundJsonToShareLink(bareVlessJson, 'plain-vless');
      expect(exportedVless).assertContain('security=none');
      expect(exportedVless).assertContain('type=tcp');
      expect(exportedVless).assertContain('headerType=none');
      const roundTripVless = parseShareLinkToOutboundJson(exportedVless);
      expect(roundTripVless.success).assertTrue();
      expect(roundTripVless.outboundJson).assertContain('"network": "tcp"');

      const exportedTrojan = formatOutboundJsonToShareLink(TROJAN_OUTBOUND, 'plain-trojan');
      expect(exportedTrojan).assertContain('security=tls');
      expect(exportedTrojan).assertContain('insecure=0');
      expect(exportedTrojan).assertContain('allowInsecure=0');
      expect(exportedTrojan).assertContain('type=tcp');
      expect(exportedTrojan).assertContain('headerType=none');
      const roundTripTrojan = parseShareLinkToOutboundJson(exportedTrojan);
      expect(roundTripTrojan.success).assertTrue();
      expect(roundTripTrojan.outboundJson).assertContain('"tlsSettings"');
      expect(roundTripTrojan.outboundJson).assertContain('"allowInsecure": false');
    });

    it('round-trips httpupgrade and xhttp transport share parameters', 0, () => {
      const httpUpgrade = parseShareLinkToOutboundJson('vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&security=tls&sni=www.example.com&type=httpupgrade&host=cdn.example&path=%2Fup#http-up');
      expect(httpUpgrade.success).assertTrue();
      expect(httpUpgrade.outboundJson).assertContain('"httpupgradeSettings"');
      expect(httpUpgrade.outboundJson).assertContain('"host": "cdn.example"');
      const exportedHttpUpgrade = formatOutboundJsonToShareLink(httpUpgrade.outboundJson, 'http-up');
      expect(exportedHttpUpgrade).assertContain('type=httpupgrade');
      expect(exportedHttpUpgrade).assertContain('host=cdn.example');
      expect(exportedHttpUpgrade).assertContain('path=%2Fup');

      const xhttp = parseShareLinkToOutboundJson('vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&security=tls&sni=www.example.com&type=xhttp&host=x.example&path=%2Fx&mode=packet-up&extra=%7B%22headers%22%3A%7B%22X-Test%22%3A%22yes%22%7D%7D#xhttp');
      expect(xhttp.success).assertTrue();
      expect(xhttp.outboundJson).assertContain('"xhttpSettings"');
      expect(xhttp.outboundJson).assertContain('"mode": "packet-up"');
      expect(xhttp.outboundJson).assertContain('"X-Test": "yes"');
      const exportedXhttp = formatOutboundJsonToShareLink(xhttp.outboundJson, 'xhttp');
      expect(exportedXhttp).assertContain('type=xhttp');
      expect(exportedXhttp).assertContain('mode=packet-up');
      expect(exportedXhttp).assertContain('extra=%7B%22headers%22%3A%7B%22X-Test%22%3A%22yes%22%7D%7D');
    });

    it('round-trips grpc multi transport mode', 0, () => {
      const grpc = parseShareLinkToOutboundJson('vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&security=tls&type=grpc&authority=grpc.example&serviceName=svc&mode=multi#grpc');
      expect(grpc.success).assertTrue();
      expect(grpc.outboundJson).assertContain('"network": "grpc"');
      expect(grpc.outboundJson).assertContain('"authority": "grpc.example"');
      expect(grpc.outboundJson).assertContain('"serviceName": "svc"');
      expect(grpc.outboundJson).assertContain('"multiMode": true');
      const exportedGrpc = formatOutboundJsonToShareLink(grpc.outboundJson, 'grpc');
      expect(exportedGrpc).assertContain('type=grpc');
      expect(exportedGrpc).assertContain('authority=grpc.example');
      expect(exportedGrpc).assertContain('serviceName=svc');
      expect(exportedGrpc).assertContain('mode=multi');
    });

    it('round-trips kcp transport share parameters', 0, () => {
      const kcp = parseShareLinkToOutboundJson('vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&type=kcp&headerType=dns&host=dns.example&seed=test-seed&mtu=1200&tti=30#kcp');
      expect(kcp.success).assertTrue();
      expect(kcp.outboundJson).assertContain('"network": "kcp"');
      expect(kcp.outboundJson).assertContain('"kcpSettings"');
      expect(kcp.outboundJson).assertContain('"mtu": 1200');
      expect(kcp.outboundJson).assertContain('"tti": 30');
      expect(kcp.outboundJson).assertContain('"type": "header-dns"');
      expect(kcp.outboundJson).assertContain('"domain": "dns.example"');
      expect(kcp.outboundJson).assertContain('"password": "test-seed"');
      const exportedKcp = formatOutboundJsonToShareLink(kcp.outboundJson, 'kcp');
      expect(exportedKcp).assertContain('type=kcp');
      expect(exportedKcp).assertContain('headerType=dns');
      expect(exportedKcp).assertContain('host=dns.example');
      expect(exportedKcp).assertContain('seed=test-seed');
      expect(exportedKcp).assertContain('mtu=1200');
      expect(exportedKcp).assertContain('tti=30');
      expect(exportedKcp.indexOf('fm=')).assertEqual(-1);

      const vmessOutboundJson = '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","security":"auto"}]}]},"streamSettings":{"network":"kcp","kcpSettings":{"mtu":1200,"tti":30},"finalmask":{"udp":[{"type":"header-wechat"},{"type":"mkcp-aes128gcm","settings":{"password":"vmess-seed"}}]}}}';
      const exportedVmess = formatOutboundJsonToShareLink(vmessOutboundJson, 'vmess-kcp');
      const importedVmess = parseShareLinkToOutboundJson(exportedVmess);
      expect(importedVmess.success).assertTrue();
      expect(importedVmess.outboundJson).assertContain('"network": "kcp"');
      expect(importedVmess.outboundJson).assertContain('"type": "header-wechat"');
      expect(importedVmess.outboundJson).assertContain('"password": "vmess-seed"');
    });

    it('round-trips v2rayNG finalMask fm share parameter', 0, () => {
      const link = 'vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&security=tls&sni=www.example.com&type=ws&host=cdn.example&path=%2Fws&fm=%7B%22tcp%22%3A%5B%7B%22type%22%3A%22fragment%22%7D%5D%7D#finalmask';
      const imported = parseShareLinkToOutboundJson(link);
      expect(imported.success).assertTrue();
      expect(imported.outboundJson).assertContain('"finalmask"');
      expect(imported.outboundJson).assertContain('"type": "fragment"');
      expect(validateOutboundJson(imported.outboundJson).valid).assertTrue();

      const exported = formatOutboundJsonToShareLink(imported.outboundJson, 'finalmask');
      expect(exported).assertContain('fm=%7B%22tcp%22%3A%5B%7B%22type%22%3A%22fragment%22%7D%5D%7D');
    });

    it('imports trojan ws tls share link as outbound json', 0, () => {
      const link = 'trojan://secret@example.com:443?security=tls&sni=trojan.example&insecure=1&type=ws&host=cdn.example&path=%2Fws#trojan-demo';
      const imported = parseShareLinkToOutboundJson(link);
      expect(imported.success).assertTrue();
      expect(imported.protocol).assertEqual('trojan');
      expect(imported.outboundJson).assertContain('"protocol": "trojan"');
      expect(imported.outboundJson).assertContain('"password": "secret"');
      expect(imported.outboundJson).assertContain('"wsSettings"');
      expect(imported.outboundJson).assertContain('"serverName": "trojan.example"');
      expect(imported.outboundJson).assertContain('"allowInsecure": true');
      const exportedTrojan = formatOutboundJsonToShareLink(imported.outboundJson, 'trojan-demo');
      expect(exportedTrojan).assertContain('insecure=1');
      expect(exportedTrojan).assertContain('allowInsecure=1');

      const aliasImported = parseShareLinkToOutboundJson('trojan://secret@example.com:443?security=tls&sni=trojan.example&allow_insecure=true&type=tcp#trojan-alias');
      expect(aliasImported.success).assertTrue();
      expect(aliasImported.outboundJson).assertContain('"allowInsecure": true');

      const mixedAliasImported = parseShareLinkToOutboundJson('trojan://secret@example.com:443?security=tls&sni=trojan.example&insecure=0&allowInsecure=1&type=tcp#trojan-mixed-alias');
      expect(mixedAliasImported.success).assertTrue();
      expect(mixedAliasImported.outboundJson).assertContain('"allowInsecure": true');

      const specialPassword = parseShareLinkToOutboundJson('trojan://sec%40ret%2Fp%3Fx@example.com:443?security=tls&sni=trojan.example&type=tcp#trojan-special');
      expect(specialPassword.success).assertTrue();
      expect(specialPassword.outboundJson).assertContain('"password": "sec@ret/p?x"');
      const exportedSpecialPassword = formatOutboundJsonToShareLink(specialPassword.outboundJson, 'trojan-special');
      expect(exportedSpecialPassword).assertContain('trojan://sec%40ret%2Fp%3Fx@example.com:443');
      expect(exportedSpecialPassword).assertContain('headerType=none');
      const roundTripSpecialPassword = parseShareLinkToOutboundJson(exportedSpecialPassword);
      expect(roundTripSpecialPassword.success).assertTrue();
      expect(roundTripSpecialPassword.outboundJson).assertContain('"password": "sec@ret/p?x"');

      const secureVless = parseShareLinkToOutboundJson('vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&security=tls&sni=vless.example&insecure=0&type=tcp#vless-secure');
      expect(secureVless.success).assertTrue();
      const exportedSecureVless = formatOutboundJsonToShareLink(secureVless.outboundJson, 'vless-secure');
      expect(exportedSecureVless).assertContain('insecure=0');
      expect(exportedSecureVless).assertContain('allowInsecure=0');
      const roundTripSecureVless = parseShareLinkToOutboundJson(exportedSecureVless);
      expect(roundTripSecureVless.success).assertTrue();
      expect(roundTripSecureVless.outboundJson).assertContain('"allowInsecure": false');
    });

    it('imports vmess and shadowsocks share links as outbound json', 0, () => {
      const vmess = 'vmess://eyJ2IjoiMiIsInBzIjoidm1lc3MtaW5zZWN1cmUiLCJhZGQiOiJleGFtcGxlLmNvbSIsInBvcnQiOiI0NDMiLCJpZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMCIsImFpZCI6IjAiLCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiJjZG4uZXhhbXBsZSIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMiLCJzbmkiOiJ2bWVzcy5leGFtcGxlIiwiZnAiOiJjaHJvbWUiLCJhbHBuIjoiaDIiLCJpbnNlY3VyZSI6IjEifQ==';
      const ss = 'ss://YWVzLTEyOC1nY206c2VjcmV0QGV4YW1wbGUuY29tOjgzODg=#ss-demo';

      const vmessResult = parseShareLinkToOutboundJson(vmess);
      expect(vmessResult.success).assertTrue();
      expect(vmessResult.outboundJson).assertContain('"protocol": "vmess"');
      expect(vmessResult.outboundJson).assertContain('"security": "auto"');
      expect(vmessResult.outboundJson).assertContain('"allowInsecure": true');
      const exportedVmess = formatOutboundJsonToShareLink(vmessResult.outboundJson, 'vmess-insecure');
      const roundTripVmess = parseShareLinkToOutboundJson(exportedVmess);
      expect(roundTripVmess.success).assertTrue();
      expect(roundTripVmess.outboundJson).assertContain('"allowInsecure": true');

      const secureVmessJson =
        '{"protocol":"vmess","tag":"proxy","settings":{"vnext":[{"address":"secure.example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","alterId":0,"security":"auto"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"secure.example.com","allowInsecure":false}}}';
      const exportedSecureVmess = formatOutboundJsonToShareLink(secureVmessJson, 'vmess-secure');
      const encodedSecureVmess = exportedSecureVmess.substring('vmess://'.length);
      const decodedSecureVmess = decodeBase64ToUtf8(encodedSecureVmess);
      expect(decodedSecureVmess).assertContain('"insecure":"0"');
      const roundTripSecureVmess = parseShareLinkToOutboundJson(exportedSecureVmess);
      expect(roundTripSecureVmess.success).assertTrue();
      expect(roundTripSecureVmess.outboundJson).assertContain('"allowInsecure": false');

      const vmessStandard = parseShareLinkToOutboundJson('vmess://00000000-0000-0000-0000-000000000000@example.com:443?security=tls&sni=std.example&type=tcp#vmess-std');
      expect(vmessStandard.success).assertTrue();
      expect(vmessStandard.outboundJson).assertContain('"security": "auto"');
      expect(outboundStreamText(vmessStandard.outboundJson, 'network')).assertEqual('tcp');
      expect(outboundStreamText(vmessStandard.outboundJson, 'security')).assertEqual('tls');
      expect(vmessStandard.outboundJson).assertContain('"serverName": "std.example"');

      const ssResult = parseShareLinkToOutboundJson(ss);
      expect(ssResult.success).assertTrue();
      expect(ssResult.outboundJson).assertContain('"protocol": "shadowsocks"');
      expect(ssResult.outboundJson).assertContain('"method": "aes-128-gcm"');
      const shortSsJson = '{"protocol":"shadowsocks","tag":"proxy","settings":{"servers":[{"address":"example.com","port":8388,"method":"aes-128-gcm","password":"p"}]}}';
      const exportedShortSs = formatOutboundJsonToShareLink(shortSsJson, 'ss-short');
      expect(exportedShortSs).assertContain('ss://YWVzLTEyOC1nY206cA@example.com:8388');
      const roundTripShortSs = parseShareLinkToOutboundJson(exportedShortSs);
      expect(roundTripShortSs.success).assertTrue();
      expect(roundTripShortSs.outboundJson).assertContain('"password": "p"');

      const obfsSs = parseShareLinkToOutboundJson('ss://YWVzLTEyOC1nY206c2VjcmV0@example.com:8388?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dcdn.example%3Bpath%3D%2Fobfs#ss-obfs');
      expect(obfsSs.success).assertTrue();
      expect(obfsSs.outboundJson).assertContain('"network": "tcp"');
      expect(obfsSs.outboundJson).assertContain('"type": "http"');
      expect(obfsSs.outboundJson).assertContain('"cdn.example"');
      expect(obfsSs.outboundJson).assertContain('"/obfs"');
      const exportedObfsSs = formatOutboundJsonToShareLink(obfsSs.outboundJson, 'ss-obfs');
      expect(exportedObfsSs).assertEqual('ss://YWVzLTEyOC1nY206c2VjcmV0@example.com:8388#ss-obfs');
      expect(exportedObfsSs.indexOf('plugin=')).assertEqual(-1);

      const legacySlash = parseShareLinkToOutboundJson('ss://QUVTLTI1Ni1HQ006cGFzczp3b3JkOndpdGg6Y29sb25zQGV4YW1wbGUuY29tOjgzODgv#Legacy%20Slash');
      expect(legacySlash.success).assertTrue();
      expect(legacySlash.name).assertEqual('Legacy Slash');
      expect(legacySlash.outboundJson).assertContain('"method": "aes-256-gcm"');
      expect(legacySlash.outboundJson).assertContain('"password": "pass:word:with:colons"');
      expect(legacySlash.outboundJson).assertContain('"address": "example.com"');
      expect(legacySlash.outboundJson).assertContain('"port": 8388');
    });

    it('defaults unnamed url-style share links to v2rayNG none remarks', 0, () => {
      const unnamedVlessLink = 'vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&type=tcp';
      const unnamedVless = parseShareLinkToOutboundJson(unnamedVlessLink);
      expect(unnamedVless.success).assertTrue();
      expect(unnamedVless.name).assertEqual('none');

      const unnamedSocks = parseShareLinkToOutboundJson('socks://example.com:1080');
      expect(unnamedSocks.success).assertTrue();
      expect(unnamedSocks.name).assertEqual('none');

      const unnamedSs = parseShareLinkToOutboundJson('ss://YWVzLTEyOC1nY206c2VjcmV0@example.com:8388');
      expect(unnamedSs.success).assertTrue();
      expect(unnamedSs.name).assertEqual('none');

      const namedTrojan = parseShareLinkToOutboundJson('trojan://secret@example.com:443?security=tls&type=tcp#named');
      expect(namedTrojan.success).assertTrue();
      expect(namedTrojan.name).assertEqual('named');

      const nodes = SubscriptionManager.parseSubscriptionContent(unnamedVlessLink, 'https://sub.example/unnamed');
      expect(nodes.length).assertEqual(1);
      expect(nodes[0].name).assertEqual('none');
    });

    it('imports socks http wireguard and hysteria2 share links as outbound json', 0, () => {
      const socks = parseShareLinkToOutboundJson('socks://dXNlcjpwYXNz@example.com:1080#socks-demo');
      expect(socks.success).assertTrue();
      expect(socks.outboundJson).assertContain('"protocol": "socks"');
      expect(socks.outboundJson).assertContain('"user": "user"');
      const exportedSocks = formatOutboundJsonToShareLink(socks.outboundJson, 'socks-demo');
      expect(exportedSocks).assertContain('socks://dXNlcjpwYXNz@example.com:1080');
      const roundTripSocks = parseShareLinkToOutboundJson(exportedSocks);
      expect(roundTripSocks.success).assertTrue();
      expect(roundTripSocks.outboundJson).assertContain('"pass": "pass"');
      const noAuthSocks = parseShareLinkToOutboundJson('socks://example.com:1080#socks-noauth');
      expect(noAuthSocks.success).assertTrue();
      const exportedNoAuthSocks = formatOutboundJsonToShareLink(noAuthSocks.outboundJson, 'socks-noauth');
      expect(exportedNoAuthSocks).assertContain('socks://Og@example.com:1080');
      const roundTripNoAuthSocks = parseShareLinkToOutboundJson(exportedNoAuthSocks);
      expect(roundTripNoAuthSocks.success).assertTrue();
      expect(roundTripNoAuthSocks.outboundJson.indexOf('"users"')).assertEqual(-1);
      const shortSocksJson = '{"protocol":"socks","tag":"proxy","settings":{"servers":[{"address":"example.com","port":1080,"users":[{"user":"u","pass":"pa"}]}]}}';
      const exportedShortSocks = formatOutboundJsonToShareLink(shortSocksJson, 'socks-short');
      expect(exportedShortSocks).assertContain('socks://dTpwYQ@example.com:1080');
      const roundTripShortSocks = parseShareLinkToOutboundJson(exportedShortSocks);
      expect(roundTripShortSocks.success).assertTrue();
      expect(roundTripShortSocks.outboundJson).assertContain('"pass": "pa"');

      const socks4 = parseShareLinkToOutboundJson('socks4://example.com:1080#socks4-demo');
      expect(socks4.success).assertTrue();
      expect(socks4.name).assertEqual('socks4-demo');
      expect(socks4.outboundJson).assertContain('"protocol": "socks"');
      const socks5 = parseShareLinkToOutboundJson('socks5://dXNlcjpwYXNz@example.com:1080#socks5-demo');
      expect(socks5.success).assertTrue();
      expect(socks5.name).assertEqual('socks5-demo');
      expect(socks5.outboundJson).assertContain('"protocol": "socks"');
      expect(socks5.outboundJson).assertContain('"user": "user"');
      expect(socks5.outboundJson).assertContain('"pass": "pass"');
      const exportedSocks5 = formatOutboundJsonToShareLink(socks5.outboundJson, 'socks5-demo');
      expect(exportedSocks5).assertContain('socks://dXNlcjpwYXNz@example.com:1080#socks5-demo');

      const http = parseShareLinkToOutboundJson('http://user:pass@example.com:8080#http-demo');
      expect(http.success).assertTrue();
      expect(http.outboundJson).assertContain('"protocol": "http"');
      expect(http.outboundJson).assertContain('"pass": "pass"');
      const specialHttp = parseShareLinkToOutboundJson('http://user%40name:p%40ss%2Fword@example.com:8080#http-special');
      expect(specialHttp.success).assertTrue();
      const exportedSpecialHttp = formatOutboundJsonToShareLink(specialHttp.outboundJson, 'http-special');
      expect(exportedSpecialHttp).assertContain('http://user%40name%3Ap%40ss%2Fword@example.com:8080');
      const roundTripSpecialHttp = parseShareLinkToOutboundJson(exportedSpecialHttp);
      expect(roundTripSpecialHttp.success).assertTrue();
      expect(roundTripSpecialHttp.outboundJson).assertContain('"user": "user@name"');
      expect(roundTripSpecialHttp.outboundJson).assertContain('"pass": "p@ss/word"');

      const wireguard = parseShareLinkToOutboundJson('wireguard://private%2Bkey%2Fwith%3D@example.com:51820?publickey=peer-key&address=172.16.0.2%2F32&mtu=1420&reserved=1%2C2%2C3#wg-demo');
      expect(wireguard.success).assertTrue();
      expect(wireguard.outboundJson).assertContain('"protocol": "wireguard"');
      expect(wireguard.outboundJson).assertContain('"secretKey": "private+key/with="');
      expect(wireguard.outboundJson).assertContain('"endpoint": "example.com:51820"');
      const exportedWireguard = formatOutboundJsonToShareLink(wireguard.outboundJson, 'wg-demo');
      expect(exportedWireguard).assertContain('wireguard://private%2Bkey%2Fwith%3D@example.com:51820');
      const roundTripWireguard = parseShareLinkToOutboundJson(exportedWireguard);
      expect(roundTripWireguard.success).assertTrue();
      expect(roundTripWireguard.outboundJson).assertContain('"secretKey": "private+key/with="');
      const defaultReservedWireguard = parseShareLinkToOutboundJson('wireguard://private-key@example.com:51820?publickey=peer-key#wg-default');
      expect(defaultReservedWireguard.success).assertTrue();
      expect(defaultReservedWireguard.outboundJson).assertContain('"reserved": [\n      0,\n      0,\n      0\n    ]');
      expect(defaultReservedWireguard.outboundJson).assertContain('"mtu": 1420');
      const exportedDefaultWireguard = formatOutboundJsonToShareLink(defaultReservedWireguard.outboundJson, 'wg-default');
      expect(exportedDefaultWireguard).assertContain('reserved=0%2C0%2C0');
      expect(exportedDefaultWireguard).assertContain('mtu=1420');

      const hysteria2 = parseShareLinkToOutboundJson('hysteria2://auth%40word%2Fwith%3F@example.com:443?sni=hy.example&insecure=1&obfs-password=obfs&mport=20000-50000&mportHopInt=10-60&pinSHA256=hy2-pinned-sha256#hy2-demo');
      expect(hysteria2.success).assertTrue();
      expect(hysteria2.outboundJson).assertContain('"protocol": "hysteria2"');
      expect(hysteria2.outboundJson).assertContain('"password": "auth@word/with?"');
      expect(hysteria2.outboundJson).assertContain('"obfsPassword": "obfs"');
      expect(hysteria2.outboundJson).assertContain('"portHopping": "20000-50000"');
      expect(hysteria2.outboundJson).assertContain('"portHoppingInterval": "10-60"');
      expect(hysteria2.outboundJson).assertContain('"pinSHA256": "hy2-pinned-sha256"');
      const exportedHy2 = formatOutboundJsonToShareLink(hysteria2.outboundJson, 'hy2-demo');
      expect(exportedHy2).assertContain('hysteria2://auth%40word%2Fwith%3F@example.com:443');
      expect(exportedHy2).assertContain('security=tls');
      expect(exportedHy2).assertContain('insecure=1');
      expect(exportedHy2).assertContain('mport=20000-50000');
      expect(exportedHy2).assertContain('mportHopInt=35');
      expect(exportedHy2).assertContain('pinSHA256=hy2-pinned-sha256');
      const roundTripHy2 = parseShareLinkToOutboundJson(exportedHy2);
      expect(roundTripHy2.success).assertTrue();
      expect(roundTripHy2.outboundJson).assertContain('"password": "auth@word/with?"');

      const secureHy2 = parseShareLinkToOutboundJson('hysteria2://secret@example.com:443?sni=secure.hy#hy2-secure');
      expect(secureHy2.success).assertTrue();
      const exportedSecureHy2 = formatOutboundJsonToShareLink(secureHy2.outboundJson, 'hy2-secure');
      expect(exportedSecureHy2).assertContain('security=tls');
      expect(exportedSecureHy2).assertContain('insecure=0');
      const roundTripSecureHy2 = parseShareLinkToOutboundJson(exportedSecureHy2);
      expect(roundTripSecureHy2.success).assertTrue();
      expect(roundTripSecureHy2.outboundJson).assertContain('"insecure": false');
    });

    it('parses base64 subscription content into selectable nodes', 0, () => {
      const content = 'dmxlc3M6Ly8wMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDBAZXhhbXBsZS5jb206NDQzP2VuY3J5cHRpb249bm9uZSZzZWN1cml0eT1yZWFsaXR5JnNuaT13d3cuZXhhbXBsZS5jb20mZnA9Y2hyb21lJnBiaz10ZXN0LXB1YmxpYy1rZXkmc2lkPWFiY2QmdHlwZT10Y3AjZGVtbwp0cm9qYW46Ly9zZWNyZXRAZXhhbXBsZS5jb206NDQzP3NlY3VyaXR5PXRscyZzbmk9dHJvamFuLmV4YW1wbGUmdHlwZT13cyZob3N0PWNkbi5leGFtcGxlJnBhdGg9JTJGd3MjdHJvamFuLWRlbW8=';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/list');
      expect(nodes.length).assertEqual(2);
      expect(nodes[0].outboundJson).assertContain('"protocol": "vless"');
      expect(nodes[1].outboundJson).assertContain('"protocol": "trojan"');
    });

    it('parses socks4 and socks5 subscription aliases into socks nodes', 0, () => {
      const content = 'socks4://example.com:1080#socks4-sub\n' +
        'socks5://dXNlcjpwYXNz@example.com:1080#socks5-sub';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/socks-aliases');
      expect(nodes.length).assertEqual(2);
      expect(nodes[0].name).assertEqual('socks4-sub');
      expect(nodes[0].outboundJson).assertContain('"protocol": "socks"');
      expect(nodes[1].name).assertEqual('socks5-sub');
      expect(nodes[1].outboundJson).assertContain('"protocol": "socks"');
      expect(nodes[1].outboundJson).assertContain('"user": "user"');
      expect(nodes[1].outboundJson).assertContain('"pass": "pass"');
    });

    it('parses data url wrapped subscription content into selectable nodes', 0, () => {
      const content = 'data:application/octet-stream;base64,dmxlc3M6Ly8wMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDBAZXhhbXBsZS5jb206NDQzP2VuY3J5cHRpb249bm9uZSNkYXRhLWRlbW8=';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/data');
      expect(nodes.length).assertEqual(1);
      expect(nodes[0].name).assertEqual('data-demo');
      expect(nodes[0].outboundJson).assertContain('"protocol": "vless"');
    });

    it('parses clash yaml subscription content into selectable nodes', 0, () => {
      const content = 'proxies:\n' +
        '  - name: clash-vmess\n' +
        '    type: vmess\n' +
        '    server: example.com\n' +
        '    port: 443\n' +
        '    uuid: 00000000-0000-0000-0000-000000000000\n' +
        '    cipher: auto\n' +
        '    tls: true\n' +
        '    network: ws\n' +
        '    ws-opts:\n' +
        '      path: /ws\n' +
        '      headers:\n' +
        '        Host: cdn.example\n' +
        '  - name: clash-reality\n' +
        '    type: vless\n' +
        '    server: reality.example.com\n' +
        '    port: 443\n' +
        '    uuid: 00000000-0000-0000-0000-000000000001\n' +
        '    flow: xtls-rprx-vision\n' +
        '    reality-opts:\n' +
        '      public-key: test-public-key\n' +
        '      short-id: abcd\n' +
        '      spider-x: /bot\n' +
        '      mldsa65-verify: test-mldsa65-verify\n' +
        '  - {name: clash-ss, type: ss, server: ss.example.com, port: 8388, cipher: aes-128-gcm, password: secret}\n';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/clash');
      expect(nodes.length).assertEqual(3);
      expect(nodes[0].name).assertEqual('clash-vmess');
      expect(nodes[0].outboundJson).assertContain('"wsSettings"');
      expect(nodes[0].outboundJson).assertContain('"serverName": "cdn.example"');
      expect(nodes[1].outboundJson).assertContain('"realitySettings"');
      expect(nodes[1].outboundJson).assertContain('"mldsa65Verify": "test-mldsa65-verify"');
      expect(nodes[2].outboundJson).assertContain('"protocol": "shadowsocks"');
    });

    it('parses sip008 shadowsocks json subscription content into selectable nodes', 0, () => {
      const content = '{"version":1,"servers":[{"remarks":"sip-node","server":"ss.example.com","server_port":8388,"method":"aes-128-gcm","password":"secret"}]}';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/sip008');
      expect(nodes.length).assertEqual(1);
      expect(nodes[0].name).assertEqual('sip-node');
      expect(nodes[0].outboundJson).assertContain('"protocol": "shadowsocks"');
      expect(nodes[0].outboundJson).assertContain('"method": "aes-128-gcm"');
    });

    it('parses xray json outbounds subscription content into selectable nodes', 0, () => {
      const content = '{"outbounds":[{"protocol":"freedom","tag":"direct","settings":{}},{"protocol":"vless","tag":"json-node","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none"}]}]}}]}';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/xray');
      expect(nodes.length).assertEqual(1);
      expect(nodes[0].name).assertEqual('json-node');
      expect(nodes[0].outboundJson).assertContain('"protocol": "vless"');
      expect(nodes[0].outboundJson).assertContain('"address": "example.com"');
    });

    it('validates insecure subscription urls like v2rayNG subscription settings', 0, () => {
      expect(SubscriptionManager.validateSubscriptionUrl('https://sub.example/list', false)).assertEqual('');
      expect(SubscriptionManager.validateSubscriptionUrl('http://sub.example/list', true)).assertEqual('');
      expect(SubscriptionManager.validateSubscriptionUrl('http://sub.example/list', false)).assertContain('不安全');
      expect(SubscriptionManager.validateSubscriptionUrl('ftp://sub.example/list', true)).assertContain('http:// 或 https://');
    });

    it('validates subscription proxy ports', 0, () => {
      expect(SubscriptionManager.shouldUseSubscriptionProxy(0)).assertFalse();
      expect(SubscriptionManager.shouldUseSubscriptionProxy(LOCAL_HTTP_PROXY_PORT)).assertTrue();
      expect(SubscriptionManager.shouldUseSubscriptionProxy(LOCAL_HTTP_PROXY_PORT + 0.5)).assertFalse();
      expect(SubscriptionManager.shouldUseSubscriptionProxy(65536)).assertFalse();
    });

    it('moves subscription groups without mutating the source list', 0, () => {
      const groups = [
        buildSubscriptionGroupFixture('sub-a', 'A'),
        buildSubscriptionGroupFixture('sub-b', 'B'),
        buildSubscriptionGroupFixture('sub-c', 'C')
      ];

      const movedUp = moveSubscriptionGroup(groups, 'sub-b', -1);
      expect(movedUp[0].id).assertEqual('sub-b');
      expect(movedUp[1].id).assertEqual('sub-a');
      expect(movedUp[2].id).assertEqual('sub-c');
      expect(groups[0].id).assertEqual('sub-a');
      expect(groups[1].id).assertEqual('sub-b');

      const movedDown = moveSubscriptionGroup(groups, 'sub-b', 1);
      expect(movedDown[0].id).assertEqual('sub-a');
      expect(movedDown[1].id).assertEqual('sub-c');
      expect(movedDown[2].id).assertEqual('sub-b');

      const outOfRange = moveSubscriptionGroup(groups, 'sub-a', -1);
      expect(outOfRange[0].id).assertEqual('sub-a');
      expect(outOfRange[1].id).assertEqual('sub-b');
      expect(outOfRange[2].id).assertEqual('sub-c');
      expect(outOfRange[0] === groups[0]).assertFalse();
    });

    it('calculates subscription auto update due windows', 0, () => {
      expect(normalizeSubscriptionUpdateInterval(undefined)).assertEqual(DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES);
      expect(normalizeSubscriptionUpdateInterval(0)).assertEqual(DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES);
      expect(normalizeSubscriptionUpdateInterval(1)).assertEqual(MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES);
      expect(normalizeSubscriptionUpdateInterval(60)).assertEqual(60);

      const group = buildSubscriptionGroupFixture('sub-auto', 'Auto');
      group.autoUpdate = true;
      group.updateIntervalMinutes = 60;
      group.updatedAt = 1000;
      expect(isSubscriptionAutoUpdateDue(group, 1000 + 59 * 60 * 1000)).assertFalse();
      expect(isSubscriptionAutoUpdateDue(group, 1000 + 60 * 60 * 1000)).assertTrue();

      group.updatedAt = 0;
      expect(isSubscriptionAutoUpdateDue(group, 2000)).assertTrue();
      group.autoUpdate = false;
      expect(isSubscriptionAutoUpdateDue(group, 2000)).assertFalse();
      group.autoUpdate = true;
      group.enabled = false;
      expect(isSubscriptionAutoUpdateDue(group, 2000)).assertFalse();
      group.enabled = true;
      group.url = '';
      expect(isSubscriptionAutoUpdateDue(group, 2000)).assertFalse();
    });

    it('parses install deep links with v2rayNG outer fragment fallback', 0, () => {
      const unnamedConfig = 'vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none';
      const config = parseDeepLink(`hey://install-config?url=${encodeURIComponent(unnamedConfig)}#outer-name`);
      expect(config.kind).assertEqual('config');
      expect(config.payload).assertEqual(`${unnamedConfig}#outer-name`);

      const namedConfig = `${unnamedConfig}#inner-name`;
      const named = parseDeepLink(`hey://install-config?url=${encodeURIComponent(namedConfig)}#outer-name`);
      expect(named.kind).assertEqual('config');
      expect(named.payload).assertEqual(namedConfig);

      const sub = parseDeepLink(`hey://install-sub?url=${encodeURIComponent('https://example.com/sub')}#Sub%20Name`);
      expect(sub.kind).assertEqual('sub');
      expect(sub.payload).assertEqual('https://example.com/sub#Sub Name');
    });

    it('extracts Harmony sendData text imports like v2rayNG ACTION_SEND', 0, () => {
      const parameters: Record<string, Object> = {};
      parameters[HARMONY_SHARE_ABSTRACT_KEY] = 'vless://abstract@example.com:443?encryption=none#abstract' as Object;
      parameters[HARMONY_SHARE_URL_KEY] = '  vless://url@example.com:443?encryption=none#url  ' as Object;

      const shared: SharedTextWantLike = {
        action: HARMONY_SEND_DATA_ACTION,
        type: HARMONY_TEXT_MIME_TYPE,
        parameters
      };
      expect(isSharedTextWant(shared)).assertTrue();
      expect(extractSharedTextFromWant(shared)).assertEqual('vless://url@example.com:443?encryption=none#url');

      const fallbackParameters: Record<string, Object> = {};
      fallbackParameters[HARMONY_SHARE_ABSTRACT_KEY] = 'vmess://payload';
      const fallback: SharedTextWantLike = {
        action: HARMONY_SEND_DATA_ACTION,
        type: 'text/plain; charset=utf-8',
        parameters: fallbackParameters
      };
      expect(extractSharedTextFromWant(fallback)).assertEqual('vmess://payload');

      const nonText: SharedTextWantLike = {
        action: HARMONY_SEND_DATA_ACTION,
        type: 'image/png',
        parameters
      };
      expect(isSharedTextWant(nonText)).assertFalse();

      const viewData: SharedTextWantLike = {
        action: 'ohos.want.action.viewData',
        type: HARMONY_TEXT_MIME_TYPE,
        parameters
      };
      expect(extractSharedTextFromWant(viewData)).assertEqual('');
    });

    it('parses control deep links for shortcut actions', 0, () => {
      const start = parseDeepLink('hey://control?action=start');
      expect(start.kind).assertEqual('control');
      expect(start.action).assertEqual('start');
      expect(start.payload).assertEqual('start');

      const stop = parseDeepLink('hey://stop');
      expect(stop.kind).assertEqual('control');
      expect(stop.action).assertEqual('stop');

      const toggle = parseDeepLink('hey://switch');
      expect(toggle.kind).assertEqual('control');
      expect(toggle.action).assertEqual('toggle');

      const scan = parseDeepLink('hey://control/scan');
      expect(scan.kind).assertEqual('control');
      expect(scan.action).assertEqual('scan');

      const invalid = parseDeepLink('hey://control?action=restart');
      expect(invalid.kind).assertEqual('none');
      const wrongHost = parseDeepLink('hey://controlx?action=start');
      expect(wrongHost.kind).assertEqual('none');
    });

    it('builds desktop control card data from supported deep links', 0, () => {
      const data = buildControlCardFormData('en');
      expect(CONTROL_CARD_FORM_NAME).assertEqual('HeyControlCard');
      expect(data.toggleUri).assertEqual(CONTROL_CARD_TOGGLE_URI);
      expect(data.startUri).assertEqual(CONTROL_CARD_START_URI);
      expect(data.stopUri).assertEqual(CONTROL_CARD_STOP_URI);
      expect(data.scanUri).assertEqual(CONTROL_CARD_SCAN_URI);
      expect(data.primaryActionUri).assertEqual(CONTROL_CARD_START_URI);
      expect(data.primaryActionLabel).assertEqual('Start');
      expect(parseDeepLink(data.toggleUri).action).assertEqual('toggle');
      expect(parseDeepLink(data.startUri).action).assertEqual('start');
      expect(parseDeepLink(data.stopUri).action).assertEqual('stop');
      expect(parseDeepLink(data.scanUri).action).assertEqual('scan');

      const running = buildControlCardFormData('en', ConnectionStatus.RUNNING, '00:03', '');
      expect(running.statusLabel).assertEqual('Running');
      expect(running.statusDetail).assertEqual('Duration 00:03');
      expect(running.primaryActionUri).assertEqual(CONTROL_CARD_STOP_URI);
      expect(running.primaryActionLabel).assertEqual('Stop');

      const errored = buildControlCardFormData('en', ConnectionStatus.ERROR, '', 'bad config');
      expect(errored.statusLabel).assertEqual('Error');
      expect(errored.statusDetail).assertEqual('bad config');
    });

    it('parses GitHub release update check results', 0, () => {
      expect(CURRENT_APP_VERSION).assertEqual('1.1.0');
      expect(normalizeVersionTag('v1.2.3-beta.1')).assertEqual('1.2.3');
      expect(compareVersions('1.10.0', '1.2.9') > 0).assertTrue();
      expect(compareVersions('1.1', '1.1.0')).assertEqual(0);
      expect(compareVersions('1.0.9', '1.1.0') < 0).assertTrue();

      const content = '{"tag_name":"v1.2.0","body":"notes","html_url":"https://example.com/release","prerelease":false,"assets":[{"name":"Hey-source.zip","browser_download_url":"https://example.com/source.zip"},{"name":"Hey-ohos-arm64.hap","browser_download_url":"https://example.com/hey.hap"}]}';
      const result = buildUpdateCheckResult(content, '1.1.0');
      expect(result.ok).assertTrue();
      expect(result.hasUpdate).assertTrue();
      expect(result.latestVersion).assertEqual('1.2.0');
      expect(result.releaseNotes).assertEqual('notes');
      expect(result.downloadUrl).assertEqual('https://example.com/hey.hap');

      const latest = buildUpdateCheckResult('{"tag_name":"v1.1.0","assets":[]}', '1.1.0');
      expect(latest.ok).assertTrue();
      expect(latest.hasUpdate).assertFalse();

      const invalid = buildUpdateCheckResult('{"body":"missing tag"}', '1.1.0');
      expect(invalid.ok).assertFalse();

      const releases = '[{"tag_name":"v1.3.0-beta.1","body":"beta","html_url":"https://example.com/beta","prerelease":true,"assets":[{"name":"Hey-beta.hap","browser_download_url":"https://example.com/beta.hap"}]},{"tag_name":"v1.2.0","body":"stable","html_url":"https://example.com/stable","prerelease":false,"assets":[{"name":"Hey-stable.hap","browser_download_url":"https://example.com/stable.hap"}]}]';
      const stableOnly = buildUpdateCheckResult(releases, '1.1.0');
      expect(stableOnly.ok).assertTrue();
      expect(stableOnly.latestVersion).assertEqual('1.2.0');
      expect(stableOnly.isPreRelease).assertFalse();
      expect(stableOnly.downloadUrl).assertEqual('https://example.com/stable.hap');

      const withPreRelease = buildUpdateCheckResult(releases, '1.1.0', true);
      expect(withPreRelease.ok).assertTrue();
      expect(withPreRelease.latestVersion).assertEqual('1.3.0');
      expect(withPreRelease.isPreRelease).assertTrue();
      expect(withPreRelease.downloadUrl).assertEqual('https://example.com/beta.hap');
    });

    it('builds subscription background auto update schedule plan', 0, () => {
      const disabled = buildSubscriptionAutoUpdateSchedulePlan([]);
      expect(disabled.enabled).assertFalse();
      expect(disabled.enabledGroupCount).assertEqual(0);
      expect(disabled.repeatCycleTimeMs).assertEqual(0);

      const hourly = buildSubscriptionGroupFixture('sub-hourly', 'Hourly');
      hourly.autoUpdate = true;
      hourly.updateIntervalMinutes = 60;
      const fast = buildSubscriptionGroupFixture('sub-fast', 'Fast');
      fast.autoUpdate = true;
      fast.updateIntervalMinutes = 5;
      const skipped = buildSubscriptionGroupFixture('sub-skipped', 'Skipped');
      skipped.autoUpdate = true;
      skipped.url = '';

      const plan = buildSubscriptionAutoUpdateSchedulePlan([hourly, fast, skipped]);
      expect(plan.enabled).assertTrue();
      expect(plan.enabledGroupCount).assertEqual(2);
      expect(plan.intervalMinutes).assertEqual(MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES);
      expect(plan.repeatCycleTimeMs).assertEqual(MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES * 60 * 1000);

      fast.enabled = false;
      const hourlyOnly = buildSubscriptionAutoUpdateSchedulePlan([hourly, fast, skipped]);
      expect(hourlyOnly.enabled).assertTrue();
      expect(hourlyOnly.enabledGroupCount).assertEqual(1);
      expect(hourlyOnly.intervalMinutes).assertEqual(60);
    });
  });
}

function buildSettingsFixture(): AppSettings {
  return {
    language: 'zh',
    uiModeNight: '0',
    speedEnabled: false,
    confirmRemove: false,
    startScanImmediate: false,
    startOnBoot: false,
    checkUpdatePreRelease: false,
    groupAllDisplay: false,
    doubleColumnDisplay: false,
    sniffingEnabled: true,
    routeOnlyEnabled: false,
    perAppProxyEnabled: false,
    perAppProxyList: [],
    perAppProxyBypass: false,
    localDnsEnabled: false,
    fakeDnsEnabled: false,
    appendHttpProxy: false,
    localSocksEnabled: false,
    localSocksPort: LOCAL_SOCKS_PROXY_PORT,
    localSocksDynamicPort: false,
    localSocksUdpEnabled: true,
    localSocksUsername: '',
    localSocksPassword: '',
    muxEnabled: false,
    muxConcurrency: 8,
    muxXudpConcurrency: 8,
    muxXudpQuic: 'reject',
    fragmentEnabled: false,
    fragmentPackets: 'tlshello',
    fragmentLength: '50-100',
    fragmentInterval: '10-20',
    ipv6Enabled: false,
    preferIpv6: false,
    proxySharingEnabled: false,
    allowInsecure: false,
    localDnsPort: 10853,
    vpnInterfaceAddressIndex: 0,
    vpnBypassLan: '1',
    vpnMtu: DEFAULT_VPN_MTU,
    vpnDns: '1.1.1.1',
    remoteDns: '1.1.1.1',
    domesticDns: '223.5.5.5',
    dnsHosts: '',
    delayTestUrl: DEFAULT_DELAY_TEST_URL,
    ipApiUrl: DEFAULT_IP_API_URL,
    realPingConcurrency: 16,
    logLevel: 'warning',
    outboundDomainResolveMethod: OUTBOUND_DOMAIN_RESOLVE_DNS_HOSTS,
    mode: 'VPN',
    trafficMode: 'rules',
    routingDomainStrategy: 'AsIs',
    adBlockEnabled: false,
    routingRules: [],
    autoSortAfterTest: false,
    autoRemoveInvalidAfterTest: false
  };
}

function buildRoutingRuleFixture(id: string, remarks: string, outboundTag: string): RoutingRule {
  return {
    id,
    remarks,
    domain: [],
    ip: [],
    process: [],
    outboundTag,
    port: '443',
    network: 'tcp',
    protocol: [],
    enabled: true,
    locked: false
  };
}

function routingRulesFromConfig(configJson: string): Array<Record<string, Object>> {
  const config = JSON.parse(configJson) as Record<string, Object>;
  const routing = config.routing as Record<string, Object>;
  const rules = routing.rules as Array<Record<string, Object>>;
  if (!Array.isArray(rules)) {
    return new Array<Record<string, Object>>();
  }
  return rules;
}

function hasRoutingInboundTag(rule: Record<string, Object>, inboundTag: string): boolean {
  const inboundTags = rule.inboundTag as Array<string>;
  return Array.isArray(inboundTags) && inboundTags.indexOf(inboundTag) >= 0;
}

function hasInboundBalancerRule(configJson: string, inboundTag: string, balancerTag: string): boolean {
  const rules = routingRulesFromConfig(configJson);
  for (let index = 0; index < rules.length; index++) {
    if (hasRoutingInboundTag(rules[index], inboundTag) && (rules[index].balancerTag as string) === balancerTag) {
      return true;
    }
  }
  return false;
}

function hasInboundOutboundRule(configJson: string, inboundTag: string, outboundTag: string): boolean {
  const rules = routingRulesFromConfig(configJson);
  for (let index = 0; index < rules.length; index++) {
    if (hasRoutingInboundTag(rules[index], inboundTag) && (rules[index].outboundTag as string) === outboundTag) {
      return true;
    }
  }
  return false;
}

function findRoutingRuleIndexByDomain(configJson: string, domain: string): number {
  const rules = routingRulesFromConfig(configJson);
  for (let index = 0; index < rules.length; index++) {
    const domains = rules[index].domain as Array<string>;
    if (Array.isArray(domains) && domains.indexOf(domain) >= 0) {
      return index;
    }
  }
  return -1;
}

function jsonArraySection(jsonText: string, key: string): string {
  const start = jsonText.indexOf(`"${key}": [`);
  if (start < 0) {
    return '';
  }
  const end = jsonText.indexOf(']', start);
  if (end < start) {
    return '';
  }
  return jsonText.substring(start, end + 1);
}

function countTextOccurrences(text: string, needle: string): number {
  let count = 0;
  let start = 0;
  while (start < text.length) {
    const next = text.indexOf(needle, start);
    if (next < 0) {
      return count;
    }
    count++;
    start = next + needle.length;
  }
  return count;
}

function outboundStreamText(outboundJson: string, key: string): string {
  const outbound = JSON.parse(outboundJson) as Record<string, Object>;
  const streamSettings = outbound.streamSettings as Record<string, Object>;
  const value = streamSettings[key];
  return typeof value === 'string' ? value : '';
}

function buildSubscriptionGroupFixture(id: string, name: string): SubscriptionGroup {
  return {
    id,
    name,
    url: `https://example.com/${id}`,
    enabled: true,
    selectedNodeId: '',
    nodes: [],
    updatedAt: 0,
    userAgent: '',
    filter: '',
    allowInsecureUrl: false,
    autoUpdate: false,
    updateIntervalMinutes: DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
  };
}

function buildNodeFixture(): Array<ProxyNode> {
  const first: ProxyNode = {
    id: 'node-alpha',
    name: 'Alpha',
    protocol: 'vless',
    outboundJson: VLESS_REALITY_OUTBOUND,
    sourceUrl: 'https://sub.example/list',
    rawLink: 'vless://alpha@example.com:443#alpha',
    updatedAt: 1,
    delayMs: 120,
    delayTestAt: 1,
    delayStatus: 'ok'
  };
  const second: ProxyNode = {
    id: 'node-beta',
    name: 'Beta',
    protocol: 'trojan',
    outboundJson: VLESS_REALITY_OUTBOUND,
    sourceUrl: 'https://sub.example/list',
    rawLink: 'trojan://secret@example.com:443#beta',
    updatedAt: 1,
    delayMs: -1,
    delayTestAt: 1,
    delayStatus: 'failed'
  };
  const manual: ProxyNode = {
    id: 'node-manual',
    name: 'Manual',
    protocol: 'vless',
    outboundJson: VLESS_REALITY_OUTBOUND,
    sourceUrl: '',
    rawLink: '',
    updatedAt: 1,
    delayMs: -1,
    delayTestAt: 0,
    delayStatus: ''
  };
  return [second, manual, first];
}

function buildGroupFixture(id: string, name: string, nodes: Array<ProxyNode>, selectedNodeId: string): SubscriptionGroup {
  return {
    id,
    name,
    url: `https://${id}.example/sub`,
    enabled: true,
    selectedNodeId,
    nodes,
    updatedAt: 1,
    userAgent: '',
    filter: '',
    allowInsecureUrl: false,
    autoUpdate: false,
    updateIntervalMinutes: DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES
  };
}

function buildAdvancedNodeFixture(): Array<ProxyNode> {
  const vless: ProxyNode = {
    id: 'advanced-vless',
    name: 'Advanced VLESS',
    protocol: 'vless',
    outboundJson: VLESS_REALITY_OUTBOUND,
    configType: 'outbound',
    sourceUrl: '',
    rawLink: '',
    updatedAt: 1,
    delayMs: -1,
    delayTestAt: 0,
    delayStatus: ''
  };
  const trojan: ProxyNode = {
    id: 'advanced-trojan',
    name: 'Advanced Trojan',
    protocol: 'trojan',
    outboundJson: TROJAN_OUTBOUND,
    configType: 'outbound',
    sourceUrl: '',
    rawLink: '',
    updatedAt: 1,
    delayMs: -1,
    delayTestAt: 0,
    delayStatus: ''
  };
  return [vless, trojan];
}

function copyNode(node: ProxyNode, id: string): ProxyNode {
  return {
    id,
    name: node.name,
    protocol: node.protocol,
    outboundJson: node.outboundJson,
    configType: node.configType,
    sourceUrl: node.sourceUrl,
    rawLink: node.rawLink,
    updatedAt: node.updatedAt,
    delayMs: node.delayMs,
    delayTestAt: node.delayTestAt,
    delayStatus: node.delayStatus
  };
}
