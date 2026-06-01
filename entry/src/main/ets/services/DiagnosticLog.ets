import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const LOG_FILE_NAME: string = 'hey-vpn-diagnostics.jsonl';
const MAX_FILE_BYTES: number = 256 * 1024;
const TRIMMED_FILE_BYTES: number = 160 * 1024;

export interface DiagnosticEvent {
  at: number;
  level: string;
  source: string;
  message: string;
  details?: string;
  uploadBytes?: number;
  downloadBytes?: number;
  xrayRunning?: boolean;
  tun2SocksRunning?: boolean;
}

export class DiagnosticLog {
  static append(context: common.Context, event: DiagnosticEvent): void {
    const path = DiagnosticLog.path(context);
    try {
      DiagnosticLog.rotateIfNeeded(path);
      const file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, `${JSON.stringify(event)}\n`);
      fs.closeSync(file);
    } catch (error) {
      console.error(`Diagnostic append failed: ${JSON.stringify(error)}`);
    }
  }

  static async read(context: common.Context, limit: number = 80): Promise<Array<DiagnosticEvent>> {
    const path = DiagnosticLog.path(context);
    try {
      if (!fs.accessSync(path)) {
        return [];
      }
      const raw = await fs.readText(path);
      return DiagnosticLog.parse(raw, limit);
    } catch (error) {
      console.error(`Diagnostic read failed: ${JSON.stringify(error)}`);
      return [];
    }
  }

  static clear(context: common.Context): void {
    const path = DiagnosticLog.path(context);
    try {
      const file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.closeSync(file);
    } catch (error) {
      console.error(`Diagnostic clear failed: ${JSON.stringify(error)}`);
    }
  }

  static format(event: DiagnosticEvent, timeFormatter: (value: number) => string): string {
    const parts: Array<string> = [`${timeFormatter(event.at)}  [${event.source}] ${event.message}`];
    if (event.details !== undefined && event.details.length > 0) {
      parts.push(event.details);
    }
    if (event.uploadBytes !== undefined || event.downloadBytes !== undefined) {
      parts.push(`up=${event.uploadBytes ?? 0} down=${event.downloadBytes ?? 0}`);
    }
    return parts.join('  ');
  }

  private static path(context: common.Context): string {
    return `${context.filesDir}/${LOG_FILE_NAME}`;
  }

  private static rotateIfNeeded(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const stat = fs.statSync(path);
      if (stat.size <= MAX_FILE_BYTES) {
        return;
      }

      const raw = fs.readTextSync(path);
      const trimmed = raw.length > TRIMMED_FILE_BYTES ? raw.slice(raw.length - TRIMMED_FILE_BYTES) : raw;
      const file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, trimmed);
      fs.closeSync(file);
    } catch (error) {
      console.error(`Diagnostic rotate failed: ${JSON.stringify(error)}`);
    }
  }

  private static parse(raw: string, limit: number): Array<DiagnosticEvent> {
    const lines = raw.split('\n').filter((line: string) => line.trim().length > 0);
    const events: Array<DiagnosticEvent> = [];
    for (let index = lines.length - 1; index >= 0 && events.length < limit; index--) {
      try {
        events.push(JSON.parse(lines[index]) as DiagnosticEvent);
      } catch (error) {
        events.push({
          at: Date.now(),
          level: 'warn',
          source: 'diagnostic',
          message: 'Skipped malformed diagnostic line.',
          details: JSON.stringify(error)
        });
      }
    }
    return events;
  }
}
