import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';

const ACTION_SEND_DATA: string = 'ohos.want.action.sendData';
const ENTITY_DEFAULT: string = 'entity.system.default';
const TEXT_MIME_TYPE: string = 'text/plain';
const CONTENT_TITLE_KEY: string = 'ohos.extra.param.key.contentTitle';
const SHARE_ABSTRACT_KEY: string = 'ohos.extra.param.key.shareAbstract';
const SHARE_URL_KEY: string = 'ohos.extra.param.key.shareUrl';

export interface TextShareResult {
  systemShareStarted: boolean;
  copiedToClipboard: boolean;
  errorMessage: string;
}

export function buildTextShareWant(title: string, content: string): Want {
  const text = content.trim();
  const parameters: Record<string, Object> = {};
  parameters[CONTENT_TITLE_KEY] = title as Object;
  parameters[SHARE_ABSTRACT_KEY] = text as Object;
  parameters[SHARE_URL_KEY] = text as Object;
  return {
    action: ACTION_SEND_DATA,
    entities: [ENTITY_DEFAULT],
    type: TEXT_MIME_TYPE,
    parameters
  };
}

export async function shareText(
  context: common.UIAbilityContext,
  title: string,
  content: string
): Promise<TextShareResult> {
  const text = content.trim();
  if (text.length === 0) {
    return {
      systemShareStarted: false,
      copiedToClipboard: false,
      errorMessage: 'empty share content'
    };
  }

  try {
    await context.startAbility(buildTextShareWant(title, text));
    return {
      systemShareStarted: true,
      copiedToClipboard: false,
      errorMessage: ''
    };
  } catch (error) {
    const shareError = stringifyError(error);
    try {
      copyTextToClipboard(text);
      return {
        systemShareStarted: false,
        copiedToClipboard: true,
        errorMessage: shareError
      };
    } catch (clipboardError) {
      return {
        systemShareStarted: false,
        copiedToClipboard: false,
        errorMessage: `${shareError}; clipboard=${stringifyError(clipboardError)}`
      };
    }
  }
}

function copyTextToClipboard(content: string): void {
  const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
  const systemPasteboard = pasteboard.getSystemPasteboard();
  systemPasteboard.setDataSync(pasteData);
}

function stringifyError(error: Object): string {
  const message = JSON.stringify(error);
  if (message !== undefined && message.length > 0) {
    return message;
  }
  return error.toString();
}
