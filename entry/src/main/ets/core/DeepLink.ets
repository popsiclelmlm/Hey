// Deep-link (URL Scheme / Want) import intents, mirroring v2rayNG's
// `install-config` / `install-sub` entry points. The app registers the scheme
//   hey://install-sub?url=<encoded subscription url>
//   hey://install-config?url=<encoded share link>
// EntryAbility stashes the raw Want uri; the Index page parses and imports it.

export type DeepLinkKind = 'sub' | 'config' | 'none';

export interface DeepLinkIntent {
  kind: DeepLinkKind;
  payload: string;
}

const SUB_PREFIX: string = 'hey://install-sub';
const CONFIG_PREFIX: string = 'hey://install-config';

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
  return { kind: 'none', payload: '' };
}

function buildIntent(kind: DeepLinkKind, uri: string): DeepLinkIntent {
  const payload = extractUrlParam(uri);
  if (payload.length === 0) {
    return { kind: 'none', payload: '' };
  }
  return { kind, payload };
}

function extractUrlParam(uri: string): string {
  const queryStart = uri.indexOf('?');
  if (queryStart < 0) {
    return '';
  }
  const query = uri.substring(queryStart + 1);
  const pairs = query.split('&');
  for (let index = 0; index < pairs.length; index++) {
    const pair = pairs[index];
    const eq = pair.indexOf('=');
    if (eq > 0 && pair.substring(0, eq) === 'url') {
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

export function subscriptionNameFromDeepLink(url: string): string {
  const stripped = url.replace('https://', '').replace('http://', '');
  const slash = stripped.indexOf('/');
  const host = slash >= 0 ? stripped.substring(0, slash) : stripped;
  return host.length > 0 ? host : 'Subscription';
}
