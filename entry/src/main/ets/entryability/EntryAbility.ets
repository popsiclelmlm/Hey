import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { applyColorMode } from '../core/ColorMode';
import { UI_MODE_NIGHT_SYSTEM } from '../core/Profile';
import { extractSharedTextFromWant } from '../core/SharedTextImport';
import { SettingsStore } from '../storage/SettingsStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.applyStoredColorMode();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    this.stashDeepLink(want);
    this.stashSharedTextImport(want);
    this.stashAutoStartupLaunch(launchParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    this.stashDeepLink(want);
    this.stashSharedTextImport(want);
  }

  // Stash a deep-link Want uri (hey://install-sub|install-config?url=...) for the
  // Index page to pick up on show. Set before the window stage loads on cold
  // start, and on every onNewWant for warm starts.
  private stashDeepLink(want: Want): void {
    const uri = want.uri;
    if (uri !== undefined && uri.length > 0) {
      AppStorage.setOrCreate('pendingDeepLink', uri);
    }
  }

  private stashSharedTextImport(want: Want): void {
    const payload = extractSharedTextFromWant({
      action: want.action,
      type: want.type,
      parameters: want.parameters
    });
    if (payload.length > 0) {
      AppStorage.setOrCreate('pendingSharedTextImport', payload);
    }
  }

  private stashAutoStartupLaunch(launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason === AbilityConstant.LaunchReason.AUTO_STARTUP) {
      AppStorage.setOrCreate('pendingAutoStartupLaunch', true);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    this.applyStoredColorMode();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  private applyStoredColorMode(): void {
    SettingsStore.load(this.context).then((settings) => {
      applyColorMode(this.context, settings.uiModeNight);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to load colorMode. Cause: %{public}s', JSON.stringify(err));
      try {
        applyColorMode(this.context, UI_MODE_NIGHT_SYSTEM);
      } catch (fallbackErr) {
        hilog.error(DOMAIN, 'testTag', 'Failed to set fallback colorMode. Cause: %{public}s', JSON.stringify(fallbackErr));
      }
    });
  }
}
