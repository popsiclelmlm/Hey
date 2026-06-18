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
    if (configType === 'outbound') {
      return 'outbound';
    }
    return ProfileStore.looksLikeFullConfig(configJson) ? 'full' : 'outbound';
  }

  private static looksLikeFullConfig(configJson: string): boolean {
    try {
      const parsed = JSON.parse(configJson) as Record<string, Object>;
      return parsed['inbounds'] !== undefined || parsed['outbounds'] !== undefined;
    } catch (error) {
      return false;
    }
  }
}
