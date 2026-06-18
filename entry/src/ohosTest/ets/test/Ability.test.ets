import { describe, it, expect } from '@ohos/hypium';
import { buildXrayConfig } from '../../../main/ets/core/XrayConfig';
import {
  BUNDLE_NAME,
  createDefaultVpnConfig,
  createStopCommandVpnWant,
  createStopVpnWant,
  createVpnWant,
  normalizeVpnDnsAddresses,
  normalizeVpnMtu,
  resolveVpnBypassLan,
  VPN_ABILITY_NAME,
  VPN_BYPASS_LAN_IPV4_ROUTES,
  VPN_COMMAND_KEY,
  VPN_COMMAND_STOP,
  VPN_MTU
} from '../../../main/ets/vpn/VpnConstants';

const OUTBOUND_JSON: string =
  '{"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"example.com","port":443,"users":[{"id":"00000000-0000-0000-0000-000000000000","encryption":"none"}]}]}}';

export default function abilityTest() {
  describe('HeyVpnAbility wiring', () => {
    it('creates a start want targeting the vpn extension', 0, () => {
      const config = buildXrayConfig(OUTBOUND_JSON);
      const want = createVpnWant(config.configJson);
      expect(want.bundleName).assertEqual(BUNDLE_NAME);
      expect(want.abilityName).assertEqual(VPN_ABILITY_NAME);
      expect(want.parameters?.['xrayConfigJson']?.toString()).assertContain('"outbounds"');
      expect(want.parameters?.['socksHost'] === undefined).assertTrue();
      expect(want.parameters?.['socksPort'] === undefined).assertTrue();
    });

    it('creates a stop want targeting the vpn extension', 0, () => {
      const want = createStopVpnWant();
      expect(want.bundleName).assertEqual(BUNDLE_NAME);
      expect(want.abilityName).assertEqual(VPN_ABILITY_NAME);
    });

    it('creates a stop command want targeting the running vpn extension', 0, () => {
      const want = createStopCommandVpnWant();
      expect(want.bundleName).assertEqual(BUNDLE_NAME);
      expect(want.abilityName).assertEqual(VPN_ABILITY_NAME);
      expect(want.parameters?.[VPN_COMMAND_KEY]?.toString()).assertEqual(VPN_COMMAND_STOP);
    });

    it('normalizes vpn dns settings for the vpn interface', 0, () => {
      expect(normalizeVpnDnsAddresses('').join('|')).assertEqual('1.1.1.1|8.8.8.8');
      expect(normalizeVpnDnsAddresses('9.9.9.9, 1.0.0.1, 9.9.9.9').join('|')).assertEqual('9.9.9.9|1.0.0.1');

      const config = createDefaultVpnConfig(false, true, [], '9.9.9.9, 1.0.0.1');
      const dnsAddresses = config.dnsAddresses === undefined ? [] : config.dnsAddresses;
      expect(dnsAddresses.join('|')).assertEqual('9.9.9.9|1.0.0.1');
      expect(config.blockedApplications?.join('|')).assertEqual(BUNDLE_NAME);
    });

    it('normalizes vpn mtu settings for the vpn interface', 0, () => {
      expect(normalizeVpnMtu()).assertEqual(VPN_MTU);
      expect(normalizeVpnMtu(1279)).assertEqual(1280);
      expect(normalizeVpnMtu(9001)).assertEqual(9000);

      const config = createDefaultVpnConfig(false, true, [], '1.1.1.1', false, 1420);
      expect(config.mtu).assertEqual(1420);
    });

    it('applies selected vpn interface address config', 0, () => {
      const config = createDefaultVpnConfig(false, true, [], '1.1.1.1', true, 1420, 5);
      expect(config.addresses[0].address.address).assertEqual('172.16.0.1');
      expect(config.addresses[1].address.address).assertEqual('fc00::172:16:0:1');

      const fallback = createDefaultVpnConfig(false, true, [], '1.1.1.1', false, 1420, 99);
      expect(fallback.addresses[0].address.address).assertEqual('10.10.14.1');
    });

    it('applies vpn bypass lan routes', 0, () => {
      const bypassConfig = createDefaultVpnConfig(false, true, [], '1.1.1.1', true, 1420, 0, '1');
      const bypassRoutes = bypassConfig.routes === undefined ? [] : bypassConfig.routes;
      expect(bypassRoutes.length).assertEqual(VPN_BYPASS_LAN_IPV4_ROUTES.length + 2);
      expect(bypassRoutes[0].destination.address.address).assertEqual('0.0.0.0');
      expect(bypassRoutes[0].destination.prefixLength).assertEqual(5);
      expect(bypassRoutes[bypassRoutes.length - 2].destination.address.address).assertEqual('2000::');
      expect(bypassRoutes[bypassRoutes.length - 2].destination.prefixLength).assertEqual(3);
      expect(bypassRoutes[bypassRoutes.length - 1].destination.address.address).assertEqual('fc00::');
      expect(bypassRoutes[bypassRoutes.length - 1].destination.prefixLength).assertEqual(18);

      const proxyConfig = createDefaultVpnConfig(false, true, [], '1.1.1.1', true, 1420, 0, '2');
      const proxyRoutes = proxyConfig.routes === undefined ? [] : proxyConfig.routes;
      expect(proxyRoutes.length).assertEqual(2);
      expect(proxyRoutes[0].destination.address.address).assertEqual('0.0.0.0');
      expect(proxyRoutes[0].destination.prefixLength).assertEqual(0);
      expect(proxyRoutes[1].destination.address.address).assertEqual('::');
      expect(proxyRoutes[1].destination.prefixLength).assertEqual(0);
    });

    it('follows direct private routing rule for auto vpn bypass lan', 0, () => {
      expect(resolveVpnBypassLan('0', [])).assertFalse();
      expect(resolveVpnBypassLan('0', [], true)).assertTrue();
      expect(resolveVpnBypassLan('0', [{
        id: 'private',
        remarks: 'Private direct',
        domain: ['geosite:private'],
        ip: ['geoip:private'],
        process: [],
        outboundTag: 'direct',
        port: '',
        network: '',
        protocol: [],
        enabled: true,
        locked: false
      }])).assertTrue();
    });

    it('adds ipv6 interface address and route when enabled', 0, () => {
      const ipv4Only = createDefaultVpnConfig(false, true, [], '1.1.1.1', false, 1400, 0, '2');
      expect(ipv4Only.isIPv6Accepted).assertFalse();
      expect(ipv4Only.addresses.length).assertEqual(1);

      const ipv6Config = createDefaultVpnConfig(false, true, [], '1.1.1.1', true, 1400, 0, '2');
      const routes = ipv6Config.routes === undefined ? [] : ipv6Config.routes;
      expect(ipv6Config.isIPv6Accepted).assertTrue();
      expect(ipv6Config.addresses.length).assertEqual(2);
      expect(ipv6Config.addresses[1].address.address).assertEqual('fc00::10:10:14:1');
      expect(ipv6Config.addresses[1].address.family).assertEqual(2);
      expect(routes.length).assertEqual(2);
      expect(routes[1].destination.address.address).assertEqual('::');
      expect(routes[1].destination.address.family).assertEqual(2);
      expect(routes[1].isDefaultRoute).assertTrue();
    });
  });
}
