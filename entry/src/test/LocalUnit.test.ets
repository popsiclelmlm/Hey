import { describe, it, expect } from '@ohos/hypium';
import { formatTranslation, missingTranslationKeys, normalizeLanguage, translate } from '../main/ets/core/I18n';
import { AppSettings, ProxyNode, RoutingRule, SubscriptionGroup } from '../main/ets/core/Profile';
import { LOCAL_HTTP_PROXY_PORT, buildXrayConfig, buildXrayConfigWithSettings, normalizeOutboundInput, validateOutboundJson } from '../main/ets/core/XrayConfig';
import { parseShareLinkToOutboundJson } from '../main/ets/core/ShareLinkParser';
import { exportRoutingRulesJson, importRoutingRulesJson, resetRoutingRulesFromPreset } from '../main/ets/core/RoutingRules';
import {
  DEFAULT_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  MIN_SUBSCRIPTION_UPDATE_INTERVAL_MINUTES,
  isSubscriptionAutoUpdateDue,
  moveSubscriptionGroup,
  normalizeSubscriptionUpdateInterval
} from '../main/ets/core/SubscriptionGroups';
import { dedupeNodes, exportNodesText, filterNodes, findInvalidNodes, sortNodes } from '../main/ets/features/nodes/NodeOperations';
import { SubscriptionManager } from '../main/ets/services/SubscriptionManager';
import { formatBytes, formatDuration } from '../main/ets/utils/Formatters';
import { formatOne, localizedProfileSavedText, localizeCoreMessage } from '../main/ets/utils/LocalizationPresenter';

const VLESS_REALITY_OUTBOUND: string =
  '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.example.com","publicKey":"test-public-key","shortId":"abcd","fingerprint":"chrome"}}}';

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
      expect(result.configJson).assertContain('"protocol": "http"');
      expect(result.configJson).assertContain(`"port": ${LOCAL_HTTP_PROXY_PORT}`);
      expect(result.configJson).assertContain('"inboundTag"');
      expect(result.configJson).assertContain('"outboundTag": "proxy"');
      expect(result.httpProxyPort).assertEqual(LOCAL_HTTP_PROXY_PORT);
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

    it('formats runtime values through shared helpers', 0, () => {
      expect(formatBytes(512)).assertEqual('512 B');
      expect(formatBytes(2048)).assertEqual('2.0 KB');
      expect(formatDuration(65)).assertEqual('01:05');
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
      expect(findInvalidNodes(nodes.concat([invalid])).length).assertEqual(1);

      const exported = exportNodesText(nodes);
      expect(exported).assertContain('vless://');
      expect(exported).assertContain('"protocol": "vless"');
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

function copyNode(node: ProxyNode, id: string): ProxyNode {
  return {
    id,
    name: node.name,
    protocol: node.protocol,
    outboundJson: node.outboundJson,
    sourceUrl: node.sourceUrl,
    rawLink: node.rawLink,
    updatedAt: node.updatedAt,
    delayMs: node.delayMs,
    delayTestAt: node.delayTestAt,
    delayStatus: node.delayStatus
  };
}
