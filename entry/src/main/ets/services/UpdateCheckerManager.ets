import { http } from '@kit.NetworkKit';
import { CURRENT_APP_VERSION, HEY_LATEST_RELEASE_API_URL, UpdateCheckResult, buildUpdateCheckResult } from '../core/UpdateChecker';

export class UpdateCheckerManager {
  async checkForUpdate(currentVersion: string = CURRENT_APP_VERSION, timeoutMs: number = 5000): Promise<UpdateCheckResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: timeoutMs,
        connectTimeout: timeoutMs,
        usingCache: false,
        header: {
          'User-Agent': 'Hey/1.1 HarmonyOS NEXT Xray Client',
          'Accept': 'application/vnd.github+json, application/json, text/plain, */*',
          'Cache-Control': 'no-cache'
        }
      };
      const response = await request.request(HEY_LATEST_RELEASE_API_URL, options);
      const responseCode = Number(response.responseCode);
      if (responseCode < 200 || responseCode >= 300) {
        return this.failed(currentVersion, `HTTP ${response.responseCode}`);
      }
      const result = buildUpdateCheckResult(this.responseText(response.result), currentVersion);
      return result.ok ? result : this.failed(currentVersion, result.error);
    } catch (error) {
      return this.failed(currentVersion, JSON.stringify(error));
    } finally {
      request.destroy();
    }
  }

  private responseText(result: Object | string | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    const text = JSON.stringify(result);
    return text === undefined ? '' : text;
  }

  private failed(currentVersion: string, error: string): UpdateCheckResult {
    return {
      ok: false,
      hasUpdate: false,
      currentVersion,
      latestVersion: '',
      releaseNotes: '',
      downloadUrl: '',
      isPreRelease: false,
      error
    };
  }
}

export const UPDATE_CHECKER_MANAGER: UpdateCheckerManager = new UpdateCheckerManager();
