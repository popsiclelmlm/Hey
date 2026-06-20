// Deep-link (URL Scheme / Want) intents, mirroring v2rayNG's
// import entry points plus shortcut/Tasker-like controls. The app registers the scheme
//   hey://install-sub?url=<encoded subscription url>
//   hey://install-config?url=<encoded share link>
//   hey://control?action=start|stop|toggle|scan
//   hey://start | hey://stop | hey://toggle | hey://scan
// EntryAbility stashes the raw Want uri or shortcut parameters; the Index page
// parses and handles it.

export type DeepLinkKind = 'sub' | 'config' | 'control' | 'none';
export type DeepLinkControlAction = 'start' | 'stop' | 'toggle' | 'scan' | '';

export const CONTROL_SHORTCUT_ACTION_PARAM: string = 'hey.control.action';
export const CONTROL_SHORTCUT_URI_PARAM: string = 'hey.control.uri';

export interface DeepLinkWantLike {
  uri?: string;
  parameters?: Record<string, Object>;
}

export interface DeepLinkIntent {
  kind: DeepLinkKind;
  payload: string;
  action?: DeepLinkControlAction;
}

const SUB_PREFIX: string = 'hey://install-sub';
const CONFIG_PREFIX: string = 'hey://install-config';
const CONTROL_PREFIX: string = 'hey://control';

export function parseDeepLink(uri: string): DeepLinkIntent {
  const trimmed = uri.trim();
  if (trimmed.length === 0) {
    return { kind: 'none', payload: '' };
  }
  const lower = trimmed.toLowerCase();
  if (lower.startsWith(SUB_PREFIX)) {
    return buildIntent('sub', trimmed);
  }
  if (lower.startsWith(CONFIG_PREFIX)) {
    return buildIntent('config', trimmed);
  }
  if (isShortcutHost(lower, 'control')) {
    return buildControlIntent(trimmed);
  }
  const action = controlActionFromShortcutHost(lower);
  if (action.length > 0) {
    return { kind: 'control', payload: action, action };
  }
  return { kind: 'none', payload: '' };
}

export function deepLinkUriFromWant(want: DeepLinkWantLike): string {
  const uri = (want.uri ?? '').trim();
  if (uri.length > 0) {
    return uri;
  }
  return controlUriFromShortcutParameters(want.parameters);
}

export function controlUriFromShortcutParameters(parameters: Record<string, Object> | undefined): string {
  if (parameters === undefined) {
    return '';
  }
  const directUri = parameterText(parameters[CONTROL_SHORTCUT_URI_PARAM]);
  if (directUri.length > 0 && parseDeepLink(directUri).kind !== 'none') {
    return directUri;
  }
  const action = normalizeControlAction(parameterText(parameters[CONTROL_SHORTCUT_ACTION_PARAM]));
  if (action.length > 0) {
    return `hey://control?action=${action}`;
  }
  return '';
}

function buildIntent(kind: DeepLinkKind, uri: string): DeepLinkIntent {
  const payload = withOuterFragmentFallback(extractUrlParam(uri), extractOuterFragment(uri));
  if (payload.length === 0) {
    return { kind: 'none', payload: '' };
  }
  return { kind, payload };
}

function buildControlIntent(uri: string): DeepLinkIntent {
  const queryAction = normalizeControlAction(extractQueryParam(uri, 'action'));
  if (queryAction.length > 0) {
    return { kind: 'control', payload: queryAction, action: queryAction };
  }

  const pathAction = normalizeControlAction(extractControlPath(uri));
  if (pathAction.length > 0) {
    return { kind: 'control', payload: pathAction, action: pathAction };
  }
  return { kind: 'none', payload: '' };
}

function extractUrlParam(uri: string): string {
  return extractQueryParam(uri, 'url');
}

function extractQueryParam(uri: string, key: string): string {
  const queryStart = uri.indexOf('?');
  if (queryStart < 0) {
    return '';
  }
  const fragmentStart = uri.indexOf('#', queryStart + 1);
  const queryEnd = fragmentStart >= 0 ? fragmentStart : uri.length;
  const query = uri.substring(queryStart + 1, queryEnd);
  const pairs = query.split('&');
  for (let index = 0; index < pairs.length; index++) {
    const pair = pairs[index];
    const eq = pair.indexOf('=');
    if (eq > 0 && pair.substring(0, eq) === key) {
      const raw = pair.substring(eq + 1);
      try {
        return decodeURIComponent(raw);
      } catch (error) {
        return raw;
      }
    }
  }
  return '';
}

function extractOuterFragment(uri: string): string {
  const queryStart = uri.indexOf('?');
  const fragmentStart = uri.indexOf('#', queryStart >= 0 ? queryStart + 1 : 0);
  if (fragmentStart < 0) {
    return '';
  }
  const raw = uri.substring(fragmentStart + 1);
  try {
    return decodeURIComponent(raw);
  } catch (error) {
    return raw;
  }
}

function withOuterFragmentFallback(payload: string, outerFragment: string): string {
  if (payload.length === 0 || outerFragment.length === 0 || payloadFragment(payload).length > 0) {
    return payload;
  }
  return `${payload}#${outerFragment}`;
}

function payloadFragment(payload: string): string {
  const fragmentStart = payload.indexOf('#');
  if (fragmentStart < 0) {
    return '';
  }
  return payload.substring(fragmentStart + 1);
}

function extractControlPath(uri: string): string {
  const lower = uri.toLowerCase();
  if (!lower.startsWith(CONTROL_PREFIX)) {
    return '';
  }
  const afterPrefix = uri.substring(CONTROL_PREFIX.length);
  if (!afterPrefix.startsWith('/')) {
    return '';
  }
  const queryStart = afterPrefix.indexOf('?');
  const path = queryStart >= 0 ? afterPrefix.substring(0, queryStart) : afterPrefix;
  return path.replace('/', '');
}

function controlActionFromShortcutHost(lowerUri: string): DeepLinkControlAction {
  if (isShortcutHost(lowerUri, 'start')) {
    return 'start';
  }
  if (isShortcutHost(lowerUri, 'stop')) {
    return 'stop';
  }
  if (isShortcutHost(lowerUri, 'toggle') || isShortcutHost(lowerUri, 'switch')) {
    return 'toggle';
  }
  if (isShortcutHost(lowerUri, 'scan')) {
    return 'scan';
  }
  return '';
}

function isShortcutHost(lowerUri: string, host: string): boolean {
  const prefix = `hey://${host}`;
  return lowerUri === prefix || lowerUri.startsWith(`${prefix}?`) || lowerUri.startsWith(`${prefix}/`);
}

function normalizeControlAction(value: string): DeepLinkControlAction {
  const normalized = value.trim().toLowerCase();
  if (normalized === 'start' || normalized === 'stop' || normalized === 'scan') {
    return normalized;
  }
  if (normalized === 'toggle' || normalized === 'switch') {
    return 'toggle';
  }
  return '';
}

function parameterText(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value.trim();
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return value.toString().trim();
  }
  return '';
}

export function subscriptionNameFromDeepLink(url: string): string {
  const stripped = url.replace('https://', '').replace('http://', '');
  const slash = stripped.indexOf('/');
  const host = slash >= 0 ? stripped.substring(0, slash) : stripped;
  return host.length > 0 ? host : 'Subscription';
}
