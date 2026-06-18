export enum AppRoute {
  INDEX = 'pages/Index',
  NODE_DETAIL = 'pages/NodeDetail',
  IMPORT = 'pages/Import',
  SUBSCRIPTIONS = 'pages/Subscriptions',
  SUBSCRIPTION_DETAIL = 'pages/SubscriptionDetail',
  SUBSCRIPTION_EDIT = 'pages/SubscriptionEdit',
  ROUTING = 'pages/Routing',
  SETTINGS = 'pages/Settings',
  PER_APP = 'pages/PerApp',
  ASSETS = 'pages/Assets',
  LOGS = 'pages/Logs',
  SCANNER = 'pages/Scanner',
  ABOUT = 'pages/About',
  EXPORT = 'pages/Export',
  NODE_EDIT = 'pages/NodeEdit',
  JSON_IMPORT = 'pages/JsonImport',
  ADVANCED_OUTBOUND = 'pages/AdvancedOutbound'
}

export interface RouteEntry {
  route: AppRoute;
  labelKey: string;
  titleKey: string;
}

export const HOME_ROUTE_ENTRIES: Array<RouteEntry> = [
  { route: AppRoute.IMPORT, labelKey: 'screen.import.label', titleKey: 'screen.import.title' },
  { route: AppRoute.SUBSCRIPTIONS, labelKey: 'screen.subscriptions.label', titleKey: 'screen.subscriptions.title' },
  { route: AppRoute.ROUTING, labelKey: 'screen.routing.label', titleKey: 'screen.routing.title' },
  { route: AppRoute.SETTINGS, labelKey: 'screen.settings.label', titleKey: 'screen.settings.title' },
  { route: AppRoute.PER_APP, labelKey: 'screen.perApp.label', titleKey: 'screen.perApp.title' },
  { route: AppRoute.ASSETS, labelKey: 'screen.assets.label', titleKey: 'screen.assets.title' },
  { route: AppRoute.LOGS, labelKey: 'screen.logs.label', titleKey: 'screen.logs.title' },
  { route: AppRoute.SCANNER, labelKey: 'screen.scanner.label', titleKey: 'screen.scanner.title' },
  { route: AppRoute.ABOUT, labelKey: 'screen.about.label', titleKey: 'screen.about.title' }
];

export function routeTitleKey(route: AppRoute): string {
  if (route === AppRoute.INDEX) {
    return 'screen.servers.title';
  }
  if (route === AppRoute.EXPORT) {
    return 'export.title';
  }
  if (route === AppRoute.NODE_DETAIL) {
    return 'node.detail.title';
  }
  if (route === AppRoute.NODE_EDIT) {
    return 'screen.nodeEdit.title';
  }
  if (route === AppRoute.JSON_IMPORT) {
    return 'screen.jsonImport.title';
  }
  if (route === AppRoute.ADVANCED_OUTBOUND) {
    return 'screen.advancedOutbound.title';
  }
  for (let index = 0; index < HOME_ROUTE_ENTRIES.length; index++) {
    const entry = HOME_ROUTE_ENTRIES[index];
    if (entry.route === route) {
      return entry.titleKey;
    }
  }
  return 'screen.servers.title';
}
