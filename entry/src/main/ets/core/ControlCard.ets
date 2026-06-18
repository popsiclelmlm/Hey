export const CONTROL_CARD_FORM_NAME: string = 'HeyControlCard';
export const CONTROL_CARD_TOGGLE_URI: string = 'hey://toggle';
export const CONTROL_CARD_START_URI: string = 'hey://start';
export const CONTROL_CARD_STOP_URI: string = 'hey://stop';
export const CONTROL_CARD_SCAN_URI: string = 'hey://scan';

export interface ControlCardFormData {
  appName: string;
  subtitle: string;
  toggleUri: string;
  startUri: string;
  stopUri: string;
  scanUri: string;
}

export function buildControlCardFormData(): ControlCardFormData {
  return {
    appName: 'Hey',
    subtitle: 'Quick proxy controls',
    toggleUri: CONTROL_CARD_TOGGLE_URI,
    startUri: CONTROL_CARD_START_URI,
    stopUri: CONTROL_CARD_STOP_URI,
    scanUri: CONTROL_CARD_SCAN_URI
  };
}
