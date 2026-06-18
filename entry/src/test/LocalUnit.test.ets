import { describe, it, expect } from '@ohos/hypium';
import { buildPolicyGroupConfigFromNodes, buildPolicyGroupConfigFromSubscription, buildProxyChainConfigFromNodes, isAdvancedOutboundBuildableNode, normalizePolicyGroupBuilderStrategy, resolveDynamicPolicyGroupConfigJson } from '../main/ets/core/AdvancedOutboundBuilder';
import { buildAppBackupPayload, buildAppBackupZipFromPayload, parseAppBackupData, parseAppBackupPayload } from '../main/ets/core/AppBackup';
import { formatTranslation, missingTranslationKeys, normalizeLanguage, translate } from '../main/ets/core/I18n';
import { defaultJsonConfigNodeName, resolveJsonConfigNodeName } from '../main/ets/core/JsonConfigNames';
import { selectRuntimeLocalSocksPort, shouldUseDynamicLocalSocksPort, withRuntimeLocalSocksPort } from '../main/ets/core/LocalProxy';
import { buildManualHysteria2Outbound, buildManualWireguardOutbound } from '../main/ets/core/ManualOutboundBuilder';
import { AppSettings, ProxyNode, RoutingRule, SubscriptionGroup } from '../main/ets/core/Profile';
import { formatGeoCountSummary, formatGeoCountUnavailable, geoDataSpecForFile, parseGeoCountData } from '../main/ets/core/GeoAssets';
import { DELAY_TEST_SOCKS_PORT, LOCAL_HTTP_PROXY_LAN_HOST, LOCAL_HTTP_PROXY_PORT, LOCAL_SOCKS_PROXY_PORT, buildDelayTestConfig, buildRuntimeXrayConfig, buildXrayConfig, buildXrayConfigWithSettings, normalizeOutboundInput, validateFullConfigJson, validateOutboundJson, validatePolicyGroupConfigJson, validateProxyChainConfigJson } from '../main/ets/core/XrayConfig';
import { extractOutboundsFromXrayConfig } from '../main/ets/core/XrayOutbounds';
import { parseShareLinkToOutboundJson } from '../main/ets/core/ShareLinkParser';
import { exportRoutingRulesJson, importRoutingRulesJson, resetRoutingRulesFromPreset } from '../main/ets/core/RoutingRules';
import {
  DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  isSubscriptionAutoUpdateDue,
  moveSubscriptionGroup,
  normalizeSubscriptionUpdateInterval
} from '../main/ets/core/SubscriptionGroups';
import { DEFAULT_WEBDAV_BACKUP_FILE_NAME, buildWebDavAuthorizationHeader, buildWebDavMkcolUrls, buildWebDavRemoteUrl, isWebDavMkcolAcceptedStatus, normalizeWebDavConfig, validateWebDavConfig } from '../main/ets/core/WebDav';
import { dedupeNodes, exportNodesText, filterNodes, findInvalidNodes, sortNodes } from '../main/ets/features/nodes/NodeOperations';
import { SETTINGS_CONTROLLER } from '../main/ets/features/settings/SettingsController';
import { SubscriptionManager } from '../main/ets/services/SubscriptionManager';
import { buildTextShareWant } from '../main/ets/services/SystemShare';
import { formatBytes, formatDuration } from '../main/ets/utils/Formatters';
import { formatOne, localizedProfileSavedText, localizeCoreMessage } from '../main/ets/utils/LocalizationPresenter';

const VLESS_REALITY_OUTBOUND: string =
  '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.example.com","publicKey":"test-public-key","shortId":"abcd","fingerprint":"chrome"}}}';
const TROJAN_OUTBOUND: string =
  '{"protocol":"trojan","tag":"relay","settings":{"servers":[{"address":"relay.example.com","port":443,"password":"secret"}]}}';
const PROXY_CHAIN_CONFIG: string =
  `{"remarks":"chain-demo","outbounds":[${VLESS_REALITY_OUTBOUND},${TROJAN_OUTBOUND}]}`;
const POLICY_GROUP_CONFIG: string =
  `{"type":"policy-group","remarks":"group-demo","strategy":"roundRobin","outbounds":[${VLESS_REALITY_OUTBOUND},${TROJAN_OUTBOUND}]}`;
const FULL_XRAY_CONFIG: string =
  '{"remarks":"Custom full config","log":{"loglevel":"info"},"inbounds":[{"tag":"tun-in","protocol":"tun","settings":{"name":"vpn-tun","mtu":1400}}],"outbounds":[{"tag":"direct","protocol":"freedom","settings":{}}],"routing":{"domainStrategy":"AsIs","rules":[]}}';
const WIREGUARD_CONF: string =
  '[Interface]\nPrivateKey = private-key\nAddress = 172.16.0.2/32, fd00::2/128\nMTU = 1420\n\n[Peer]\nPublicKey = peer-key\nPresharedKey = shared-key\nEndpoint = wg.example.com:51820\nReserved = 1,2,3\nAllowedIPs = 0.0.0.0/0, ::/0\n';

export default function localUnitTest() {
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

      const result = buildRuntimeXrayConfig(validation.normalizedJson, buildSettingsFixture(), 'proxy-chain');
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
      settings.appendHttpProxy = true;
      const result = buildRuntimeXrayConfig(validation.normalizedJson, settings, 'policy-group');
      expect(result.configJson).assertContain('"tag": "proxy-policy-group-1"');
      expect(result.configJson).assertContain('"tag": "proxy-policy-group-2"');
      expect(result.configJson).assertContain('"tag": "balancer"');
      expect(result.configJson).assertContain('"selector": [');
      expect(result.configJson).assertContain('"proxy-policy-group-"');
      expect(result.configJson).assertContain('"type": "roundRobin"');
      expect(result.configJson).assertContain('"balancerTag": "balancer"');
      expect(result.configJson).assertContain('"inboundTag": [\n        "http-in"');
      expect(result.httpProxyPort).assertEqual(LOCAL_HTTP_PROXY_PORT);

      const leastLoad = buildRuntimeXrayConfig(`{"type":"policy-group","policyGroupType":"1","outbounds":[${VLESS_REALITY_OUTBOUND}]}`, settings, 'policy-group');
      expect(leastLoad.configJson).assertContain('"type": "leastLoad"');
      expect(leastLoad.configJson).assertContain('"burstObservatory"');
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
        bandwidthDown: '100 mbps',
        bandwidthUp: '20 mbps'
      });
      expect(hysteria2.success).assertTrue();
      expect(hysteria2.outboundJson).assertContain('"protocol": "hysteria2"');
      expect(hysteria2.outboundJson).assertContain('"portHopping": "20000-50000"');
      expect(hysteria2.outboundJson).assertContain('"obfsPassword": "obfs-secret"');
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
        bandwidthDown: '',
        bandwidthUp: ''
      }).success).assertFalse();
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

      const missingEndpoint = normalizeOutboundInput('[Interface]\nPrivateKey = private-key\n[Peer]\nPublicKey = peer-key\n');
      expect(missingEndpoint.valid).assertFalse();
      expect(localizeCoreMessage('en', missingEndpoint.message)).assertEqual('WireGuard config is missing endpoint.');
    });

    it('applies app settings when generating xray config', 0, () => {
      const settings: AppSettings = {
        language: 'zh',
        sniffingEnabled: true,
        routeOnlyEnabled: true,
        perAppProxyEnabled: false,
        perAppProxyList: [],
        perAppProxyBypass: true,
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
        preferIpv6: false,
        proxySharingEnabled: false,
        allowInsecure: false,
        localDnsPort: 10853,
        vpnInterfaceAddressIndex: 0,
        vpnBypassLan: '1',
        vpnMtu: 1400,
        vpnDns: '1.1.1.1',
        remoteDns: '9.9.9.9',
        domesticDns: '223.5.5.5',
        dnsHosts: '',
        delayTestUrl: 'https://www.gstatic.com/generate_204',
        logLevel: 'debug',
        mode: 'VPN',
        trafficMode: 'rules',
        routingDomainStrategy: 'IPIfNonMatch',
        adBlockEnabled: false,
        routingRules: [],
        autoSortAfterTest: false,
        autoRemoveInvalidAfterTest: false
      };
      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"loglevel": "debug"');
      expect(result.configJson).assertContain('"domainStrategy": "IPIfNonMatch"');
      expect(result.configJson).assertContain('"geosite:cn"');
      expect(result.configJson).assertContain('"sniffing"');
      expect(result.configJson).assertContain('"mux"');
      expect(result.configJson).assertContain('"9.9.9.9"');
    });

    it('applies local dns and fakedns settings to generated xray config', 0, () => {
      const settings = buildSettingsFixture();
      settings.localDnsEnabled = true;
      settings.fakeDnsEnabled = true;
      settings.sniffingEnabled = false;
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
      const result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"tag": "dns-out"');
      expect(result.configJson).assertContain('"protocol": "dns"');
      expect(result.configJson).assertContain('"port": "53"');
      expect(result.configJson).assertContain('"fakedns"');
      expect(result.configJson).assertContain('"geosite:cn"');
      expect(result.configJson).assertContain('"domain:proxy.example"');
      expect(result.configJson).assertContain('"destOverride"');
    });

    it('applies vpn mtu to generated tun inbound', 0, () => {
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
          ip: ['geoip:private'],
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
      expect(result.configJson).assertContain('"geoip:private"');
      expect(result.configJson).assertContain('"port": "443"');
      expect(result.configJson).assertContain('"network": "tcp"');
      expect(result.configJson).assertContain('"tls"');
      expect(result.configJson).assertContain('"geosite:category-ads-all"');
      expect(result.configJson).assertContain('"geosite:cn"');
      expect(result.configJson.indexOf('domain:disabled.example')).assertEqual(-1);
      expect(result.configJson.indexOf('geosite:category-ads-all') < result.configJson.indexOf('domain:example.com')).assertTrue();
      expect(result.configJson.indexOf('domain:example.com') < result.configJson.indexOf('geosite:cn')).assertTrue();
    });

    it('appends local http proxy inbound when enabled', 0, () => {
      const settings = buildSettingsFixture();
      let result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson.indexOf('"tag": "http-in"')).assertEqual(-1);

      settings.appendHttpProxy = true;
      result = buildXrayConfigWithSettings(VLESS_REALITY_OUTBOUND, settings);
      expect(result.configJson).assertContain('"tag": "http-in"');
      expect(result.configJson).assertContain('"listen": "127.0.0.1"');
      expect(result.configJson).assertContain('"protocol": "http"');
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
    });

    it('uses requested socks port for delay test config', 0, () => {
      const customPort = 19081;
      const result = buildDelayTestConfig(VLESS_REALITY_OUTBOUND, customPort);
      expect(result.configJson).assertContain('"tag":"socks-in"');
      expect(result.configJson).assertContain(`"port":${customPort}`);
      expect(result.configJson.indexOf(`"port":${DELAY_TEST_SOCKS_PORT}`)).assertEqual(-1);
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
      expect(result.configJson).assertContain('"fragment"');
      expect(result.configJson).assertContain('"tlshello"');
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
      expect(translate('zh', 'missing.translation.key')).assertEqual('missing.translation.key');
      expect(formatTranslation('en', 'subscription.updateComplete', ['count'], ['3'])).assertContain('3');
      expect(formatOne('zh', 'subscription.updateComplete', 'count', '3')).assertContain('3');
      expect(localizedProfileSavedText('en', 0)).assertEqual('Not saved');
      expect(localizeCoreMessage('en', '请先粘贴 Xray outbound JSON。')).assertEqual('Paste Xray outbound JSON first.');
      expect(normalizeLanguage('en')).assertEqual('en');
      expect(normalizeLanguage('zh')).assertEqual('zh');
      expect(normalizeLanguage('fr')).assertEqual('zh');
    });

    it('formats geo asset count status', 0, () => {
      const geosite = geoDataSpecForFile('geosite.dat');
      const geoip = geoDataSpecForFile('geoip.dat');
      expect(geosite?.name).assertEqual('geosite');
      expect(geosite?.geoType).assertEqual('domain');
      expect(geoip?.name).assertEqual('geoip');
      expect(geoip?.geoType).assertEqual('ip');
      expect(geoDataSpecForFile('custom.dat') === null).assertTrue();

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

    it('round-trips vpn settings through settings draft', 0, () => {
      const settings = buildSettingsFixture();
      settings.preferIpv6 = true;
      settings.localDnsPort = 1053;
      settings.localSocksEnabled = true;
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
      const draft = SETTINGS_CONTROLLER.toDraft(settings);
      expect(draft.preferIpv6).assertTrue();
      expect(draft.localDnsPort).assertEqual('1053');
      expect(draft.localSocksEnabled).assertTrue();
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
      const rebuilt = SETTINGS_CONTROLLER.buildSettings(draft);
      expect(rebuilt.preferIpv6).assertTrue();
      expect(rebuilt.localDnsPort).assertEqual(1053);
      expect(rebuilt.localSocksEnabled).assertTrue();
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
      expect(SETTINGS_CONTROLLER.buildSettings(draft).vpnMtu).assertEqual(1400);
      draft.vpnMtu = '';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).vpnMtu).assertEqual(1400);
      draft.muxConcurrency = '0';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxConcurrency).assertEqual(8);
      draft.muxXudpConcurrency = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpConcurrency).assertEqual(8);
      draft.muxXudpQuic = 'bad';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).muxXudpQuic).assertEqual('reject');
      draft.fragmentPackets = '';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).fragmentPackets).assertEqual('tlshello');
      draft.logLevel = 'verbose';
      expect(SETTINGS_CONTROLLER.buildSettings(draft).logLevel).assertEqual('warning');
    });

    it('formats runtime values through shared helpers', 0, () => {
      expect(formatBytes(512)).assertEqual('512 B');
      expect(formatBytes(2048)).assertEqual('2.0 KB');
      expect(formatDuration(65)).assertEqual('01:05');
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

    it('finds invalid nodes and exports raw links or outbound json', 0, () => {
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

      const exported = exportNodesText(nodes.concat([fullConfigNode]));
      expect(exported).assertContain('vless://');
      expect(exported).assertContain('"protocol": "vless"');
      expect(exported).assertContain('"remarks": "Custom full config"');
    });

    it('imports vless reality share link as outbound json', 0, () => {
      const link = 'vless://00000000-0000-0000-0000-000000000000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=test-public-key&sid=abcd&type=tcp#demo';
      const imported = parseShareLinkToOutboundJson(link);
      expect(imported.success).assertTrue();
      expect(imported.protocol).assertEqual('vless');
      expect(imported.outboundJson).assertContain('"protocol": "vless"');
      expect(imported.outboundJson).assertContain('"realitySettings"');
      expect(imported.outboundJson).assertContain('"publicKey": "test-public-key"');

      const validation = normalizeOutboundInput(link);
      expect(validation.valid).assertTrue();
      expect(validation.normalizedJson).assertContain('"flow": "xtls-rprx-vision"');
    });

    it('imports trojan ws tls share link as outbound json', 0, () => {
      const link = 'trojan://secret@example.com:443?security=tls&sni=trojan.example&type=ws&host=cdn.example&path=%2Fws#trojan-demo';
      const imported = parseShareLinkToOutboundJson(link);
      expect(imported.success).assertTrue();
      expect(imported.protocol).assertEqual('trojan');
      expect(imported.outboundJson).assertContain('"protocol": "trojan"');
      expect(imported.outboundJson).assertContain('"password": "secret"');
      expect(imported.outboundJson).assertContain('"wsSettings"');
      expect(imported.outboundJson).assertContain('"serverName": "trojan.example"');
    });

    it('imports vmess and shadowsocks share links as outbound json', 0, () => {
      const vmess = 'vmess://eyJ2IjoiMiIsInBzIjoidm1lc3MtZGVtbyIsImFkZCI6ImV4YW1wbGUuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiMDAwMDAwMDAtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAwIiwiYWlkIjoiMCIsInNjeSI6ImF1dG8iLCJuZXQiOiJ3cyIsInR5cGUiOiJub25lIiwiaG9zdCI6ImNkbi5leGFtcGxlIiwicGF0aCI6Ii93cyIsInRscyI6InRscyIsInNuaSI6InZtZXNzLmV4YW1wbGUiLCJmcCI6ImNocm9tZSIsImFscG4iOiJoMiJ9';
      const ss = 'ss://YWVzLTEyOC1nY206c2VjcmV0QGV4YW1wbGUuY29tOjgzODg=#ss-demo';

      const vmessResult = parseShareLinkToOutboundJson(vmess);
      expect(vmessResult.success).assertTrue();
      expect(vmessResult.outboundJson).assertContain('"protocol": "vmess"');
      expect(vmessResult.outboundJson).assertContain('"security": "auto"');

      const ssResult = parseShareLinkToOutboundJson(ss);
      expect(ssResult.success).assertTrue();
      expect(ssResult.outboundJson).assertContain('"protocol": "shadowsocks"');
      expect(ssResult.outboundJson).assertContain('"method": "aes-128-gcm"');
    });

    it('imports socks http wireguard and hysteria2 share links as outbound json', 0, () => {
      const socks = parseShareLinkToOutboundJson('socks://dXNlcjpwYXNz@example.com:1080#socks-demo');
      expect(socks.success).assertTrue();
      expect(socks.outboundJson).assertContain('"protocol": "socks"');
      expect(socks.outboundJson).assertContain('"user": "user"');

      const http = parseShareLinkToOutboundJson('http://user:pass@example.com:8080#http-demo');
      expect(http.success).assertTrue();
      expect(http.outboundJson).assertContain('"protocol": "http"');
      expect(http.outboundJson).assertContain('"pass": "pass"');

      const wireguard = parseShareLinkToOutboundJson('wireguard://private-key@example.com:51820?publickey=peer-key&address=172.16.0.2%2F32&mtu=1420&reserved=1%2C2%2C3#wg-demo');
      expect(wireguard.success).assertTrue();
      expect(wireguard.outboundJson).assertContain('"protocol": "wireguard"');
      expect(wireguard.outboundJson).assertContain('"endpoint": "example.com:51820"');

      const hysteria2 = parseShareLinkToOutboundJson('hysteria2://auth@example.com:443?sni=hy.example&insecure=1&obfs-password=obfs#hy2-demo');
      expect(hysteria2.success).assertTrue();
      expect(hysteria2.outboundJson).assertContain('"protocol": "hysteria2"');
      expect(hysteria2.outboundJson).assertContain('"obfsPassword": "obfs"');
    });

    it('parses base64 subscription content into selectable nodes', 0, () => {
      const content = 'dmxlc3M6Ly8wMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDBAZXhhbXBsZS5jb206NDQzP2VuY3J5cHRpb249bm9uZSZzZWN1cml0eT1yZWFsaXR5JnNuaT13d3cuZXhhbXBsZS5jb20mZnA9Y2hyb21lJnBiaz10ZXN0LXB1YmxpYy1rZXkmc2lkPWFiY2QmdHlwZT10Y3AjZGVtbwp0cm9qYW46Ly9zZWNyZXRAZXhhbXBsZS5jb206NDQzP3NlY3VyaXR5PXRscyZzbmk9dHJvamFuLmV4YW1wbGUmdHlwZT13cyZob3N0PWNkbi5leGFtcGxlJnBhdGg9JTJGd3MjdHJvamFuLWRlbW8=';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/list');
      expect(nodes.length).assertEqual(2);
      expect(nodes[0].outboundJson).assertContain('"protocol": "vless"');
      expect(nodes[1].outboundJson).assertContain('"protocol": "trojan"');
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
        '  - {name: clash-ss, type: ss, server: ss.example.com, port: 8388, cipher: aes-128-gcm, password: secret}\n';
      const nodes = SubscriptionManager.parseSubscriptionContent(content, 'https://sub.example/clash');
      expect(nodes.length).assertEqual(2);
      expect(nodes[0].name).assertEqual('clash-vmess');
      expect(nodes[0].outboundJson).assertContain('"wsSettings"');
      expect(nodes[0].outboundJson).assertContain('"serverName": "cdn.example"');
      expect(nodes[1].outboundJson).assertContain('"protocol": "shadowsocks"');
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
      expect(SubscriptionManager.shouldUseSubscriptionProxy(10808)).assertTrue();
      expect(SubscriptionManager.shouldUseSubscriptionProxy(10808.5)).assertFalse();
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
  });
}

function buildSettingsFixture(): AppSettings {
  return {
    language: 'zh',
    sniffingEnabled: true,
    routeOnlyEnabled: false,
    perAppProxyEnabled: false,
    perAppProxyList: [],
    perAppProxyBypass: true,
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
    preferIpv6: false,
    proxySharingEnabled: false,
    allowInsecure: false,
    localDnsPort: 10853,
    vpnInterfaceAddressIndex: 0,
    vpnBypassLan: '1',
    vpnMtu: 1400,
    vpnDns: '1.1.1.1',
    remoteDns: '1.1.1.1',
    domesticDns: '223.5.5.5',
    dnsHosts: '',
    delayTestUrl: 'https://www.gstatic.com/generate_204',
    logLevel: 'warning',
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
