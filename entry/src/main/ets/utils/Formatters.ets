import { ConnectionStatus } from '../core/Profile';

export function formatBytes(value: number): string {
  if (value >= 1024 * 1024) {
    return `${(value / 1024 / 1024).toFixed(1)} MB`;
  }
  if (value >= 1024) {
    return `${(value / 1024).toFixed(1)} KB`;
  }
  return `${value} B`;
}

export function formatClockTime(value: number): string {
  const date = new Date(value);
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}

export function formatDuration(seconds: number): string {
  const minutes = Math.floor(seconds / 60);
  const remain = seconds % 60;
  return `${pad2(minutes)}:${pad2(remain)}`;
}

export function connectionStatusColor(status: ConnectionStatus): string {
  if (status === ConnectionStatus.RUNNING) {
    return '#166534';
  }
  if (status === ConnectionStatus.ERROR) {
    return '#B42318';
  }
  if (status === ConnectionStatus.STARTING || status === ConnectionStatus.STOPPING) {
    return '#92400E';
  }
  return '#374151';
}

export function connectionStatusBackground(status: ConnectionStatus): string {
  if (status === ConnectionStatus.RUNNING) {
    return '#DCFCE7';
  }
  if (status === ConnectionStatus.ERROR) {
    return '#FEF3F2';
  }
  if (status === ConnectionStatus.STARTING || status === ConnectionStatus.STOPPING) {
    return '#FEF3C7';
  }
  return '#F3F4F6';
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : value.toString();
}
