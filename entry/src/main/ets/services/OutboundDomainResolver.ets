import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { AppSettings, OUTBOUND_DOMAIN_RESOLVE_NONE, XrayConfigType } from '../core/Profile';
import { collectOutboundDomainPreResolveHosts, withOutboundDomainResolvedHosts } from '../core/XrayConfig';
import { DiagnosticLog } from './DiagnosticLog';

const DNS_PRE_RESOLVE_TIMEOUT_MS: number = 4000;
const DNS_PRE_RESOLVE_CONCURRENCY: number = 8;

interface HostResolveResult {
  host: string;
  addresses: Array<string>;
  error?: string;
}

export class OutboundDomainResolver {
  async resolve(
    context: common.Context,
    configJson: string,
    settings?: AppSettings,
    configType?: XrayConfigType
  ): Promise<AppSettings | undefined> {
    if (settings === undefined || settings.outboundDomainResolveMethod === OUTBOUND_DOMAIN_RESOLVE_NONE || configType === 'full') {
      return settings;
    }

    let hosts = new Array<string>();
    try {
      hosts = collectOutboundDomainPreResolveHosts(configJson, settings, configType);
    } catch (error) {
      this.appendDiagnostic(context, 'warn', 'Outbound domain pre-resolve skipped.', this.formatError(error as Object));
      return settings;
    }
    if (hosts.length === 0) {
      return settings;
    }

    this.appendDiagnostic(context, 'info', 'Outbound domain pre-resolve requested.', `hosts=${hosts.length}`);
    const results = await this.resolveHosts(hosts);
    const resolvedHosts: Record<string, Array<string>> = {};
    const failedHosts = new Array<string>();
    for (let index = 0; index < results.length; index++) {
      const result = results[index];
      if (result.addresses.length > 0) {
        resolvedHosts[result.host] = result.addresses;
      } else {
        failedHosts.push(result.host);
      }
    }

    const resolvedKeys = Object.keys(resolvedHosts);
    if (resolvedKeys.length === 0) {
      this.appendDiagnostic(context, 'warn', 'Outbound domain pre-resolve returned no addresses.', `failed=${failedHosts.join(',')}`);
      return settings;
    }

    const runtimeSettings = withOutboundDomainResolvedHosts(settings, resolvedHosts);
    this.appendDiagnostic(
      context,
      'info',
      'Outbound domain pre-resolve completed.',
      `resolved=${resolvedKeys.length}/${hosts.length}; failed=${failedHosts.length}`
    );
    return runtimeSettings;
  }

  private async resolveHosts(hosts: Array<string>): Promise<Array<HostResolveResult>> {
    const results = new Array<HostResolveResult>();
    for (let index = 0; index < hosts.length; index += DNS_PRE_RESOLVE_CONCURRENCY) {
      const batch = hosts.slice(index, index + DNS_PRE_RESOLVE_CONCURRENCY);
      const batchResults = await Promise.all(batch.map((host: string): Promise<HostResolveResult> => {
        return this.resolveHost(host);
      }));
      for (let resultIndex = 0; resultIndex < batchResults.length; resultIndex++) {
        results.push(batchResults[resultIndex]);
      }
    }
    return results;
  }

  private async resolveHost(host: string): Promise<HostResolveResult> {
    try {
      const addresses = await this.withTimeout(
        connection.getAddressesByName(host),
        DNS_PRE_RESOLVE_TIMEOUT_MS,
        `resolve timeout: ${host}`
      );
      const normalized = this.normalizeAddresses(addresses);
      return {
        host,
        addresses: normalized,
        error: normalized.length === 0 ? 'empty result' : undefined
      };
    } catch (error) {
      return {
        host,
        addresses: [],
        error: this.formatError(error as Object)
      };
    }
  }

  private normalizeAddresses(values: Array<connection.NetAddress>): Array<string> {
    const seen: Record<string, boolean> = {};
    const addresses = new Array<string>();
    for (let index = 0; index < values.length; index++) {
      const address = values[index].address.trim();
      if (address.length === 0 || seen[address]) {
        continue;
      }
      seen[address] = true;
      addresses.push(address);
    }
    return addresses;
  }

  private withTimeout<T>(operation: Promise<T>, timeoutMs: number, message: string): Promise<T> {
    return new Promise<T>((resolve: (value: T | PromiseLike<T>) => void, reject: (reason?: Object) => void) => {
      const timerId = setTimeout(() => {
        reject(new Error(message));
      }, timeoutMs);

      operation.then((value: T) => {
        clearTimeout(timerId);
        resolve(value);
      }).catch((error: BusinessError) => {
        clearTimeout(timerId);
        reject(error);
      });
    });
  }

  private appendDiagnostic(context: common.Context, level: string, message: string, details: string): void {
    DiagnosticLog.append(context, {
      at: Date.now(),
      level,
      source: 'dns',
      message,
      details
    });
  }

  private formatError(error: Object): string {
    const businessError = error as BusinessError;
    if (businessError.message !== undefined && businessError.message.length > 0) {
      return businessError.message;
    }
    const formatted = JSON.stringify(error);
    return formatted === undefined ? 'unknown error' : formatted;
  }
}

export const OUTBOUND_DOMAIN_RESOLVER: OutboundDomainResolver = new OutboundDomainResolver();
