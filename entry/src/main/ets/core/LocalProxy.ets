import { AppSettings, isProxyOnlyRuntimeMode } from './Profile';

export function shouldUseDynamicLocalSocksPort(settings: AppSettings | undefined): boolean {
  return settings !== undefined && (settings.localSocksEnabled || isProxyOnlyRuntimeMode(settings.mode)) && settings.localSocksDynamicPort;
}

export function selectRuntimeLocalSocksPort(settings: AppSettings, freePorts: Array<number>, reservedPorts: Array<number> = []): number {
  if (!shouldUseDynamicLocalSocksPort(settings)) {
    return settings.localSocksPort;
  }
  for (let index = 0; index < freePorts.length; index++) {
    const port = freePorts[index];
    if (isValidPort(port) && reservedPorts.indexOf(port) < 0) {
      return port;
    }
  }
  return settings.localSocksPort;
}

export function withRuntimeLocalSocksPort(settings: AppSettings, port: number): AppSettings {
  const runtimeSettings = JSON.parse(JSON.stringify(settings)) as AppSettings;
  runtimeSettings.localSocksPort = isValidPort(port) ? port : settings.localSocksPort;
  return runtimeSettings;
}

function isValidPort(port: number): boolean {
  return typeof port === 'number' && Math.floor(port) === port && port >= 1 && port <= 65535;
}
