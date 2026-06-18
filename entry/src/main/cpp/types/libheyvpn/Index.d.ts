export interface NativeResult {
  ok: boolean;
  message: string;
}

export interface NativePingResult {
  ok: boolean;
  delayMs: number;
  message: string;
}

export interface RuntimeStats {
  uploadBytes: number;
  downloadBytes: number;
  xrayRunning: boolean;
  tunRunning: boolean;
  lastMessage: string;
}

export const validateConfig: (configJson: string) => NativeResult;
export const setTunFd: (tunFd: number) => NativeResult;
export const startXray: (configJson: string, workDir: string) => NativeResult;
export const stopXray: () => NativeResult;
export const getStats: () => RuntimeStats;
export const pingOutbound: (configJson: string, datDir: string, url: string, timeoutSeconds: number, proxy: string) => NativePingResult;
export const queryStats: (server: string) => NativeResult;
export const testXrayConfig: (configJson: string, workDir: string) => NativeResult;
export const xrayVersion: () => NativeResult;
export const countGeoData: (datDir: string, name: string, geoType: string) => NativeResult;
export const readGeoFiles: (configJson: string) => NativeResult;
