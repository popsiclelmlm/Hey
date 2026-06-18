import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DEFAULT_PROFILE_ID, ProxyProfile, XrayConfigType } from '../core/Profile';

const PREFERENCES_NAME: string = 'hey_vpn_profile';
const PROFILE_KEY: string = 'default_profile';

export class ProfileStore {
  static async load(context: common.Context): Promise<ProxyProfile> {
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    const rawValue = await store.get(PROFILE_KEY, '');
    const raw = rawValue.toString();
    if (raw.length === 0) {
      return ProfileStore.createEmptyProfile();
    }

    try {
      const profile = JSON.parse(raw) as ProxyProfile;
      if (profile.id === undefined || profile.id.length === 0) {
        return ProfileStore.createEmptyProfile();
      }
      return {
        id: profile.id,
        name: profile.name ?? 'Default Xray Profile',
        outboundJson: profile.outboundJson ?? '',
        configType: ProfileStore.normalizeConfigType(profile.configType, profile.outboundJson ?? ''),
        updatedAt: profile.updatedAt ?? 0
      };
    } catch (error) {
      return ProfileStore.createEmptyProfile();
    }
  }

  static async save(context: common.Context, outboundJson: string, configType: XrayConfigType = 'outbound'): Promise<ProxyProfile> {
    const profile: ProxyProfile = {
      id: DEFAULT_PROFILE_ID,
      name: 'Default Xray Profile',
      outboundJson,
      configType: ProfileStore.normalizeConfigType(configType),
      updatedAt: Date.now()
    };
    const store = await preferences.getPreferences(context, PREFERENCES_NAME);
    await store.put(PROFILE_KEY, JSON.stringify(profile));
    await store.flush();
    return profile;
  }

  private static createEmptyProfile(): ProxyProfile {
    return {
      id: DEFAULT_PROFILE_ID,
      name: 'Default Xray Profile',
      outboundJson: '',
      configType: 'outbound',
      updatedAt: 0
    };
  }

  private static normalizeConfigType(configType?: XrayConfigType, configJson: string = ''): XrayConfigType {
    if (configType === 'full') {
      return 'full';
    }
    if (configType === 'proxy-chain') {
      return 'proxy-chain';
    }
    if (configType === 'policy-group') {
      return 'policy-group';
    }
    if (configType === 'outbound') {
      return 'outbound';
    }
    const detected = ProfileStore.detectConfigType(configJson);
    return detected ?? 'outbound';
  }

  private static detectConfigType(configJson: string): XrayConfigType | null {
    try {
      const parsed = JSON.parse(configJson) as Record<string, Object>;
      if (Array.isArray(parsed) || (Array.isArray(parsed['outbounds']) &&
        parsed['inbounds'] === undefined &&
        parsed['routing'] === undefined &&
        parsed['dns'] === undefined &&
        parsed['log'] === undefined)) {
        const type = typeof parsed['type'] === 'string' ? (parsed['type'] as string).toLowerCase() : '';
        const configType = typeof parsed['configType'] === 'string' ? (parsed['configType'] as string).toLowerCase() : '';
        if (type === 'policy-group' || configType === 'policy-group' ||
          parsed['strategy'] !== undefined || parsed['policyGroupType'] !== undefined) {
          return 'policy-group';
        }
        return 'proxy-chain';
      }
      return parsed['inbounds'] !== undefined || parsed['outbounds'] !== undefined ? 'full' : null;
    } catch (error) {
      return null;
    }
  }
}
