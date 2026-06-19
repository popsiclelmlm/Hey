const BASE64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function stripWhitespace(value: string): string {
  let result = '';
  for (let index = 0; index < value.length; index++) {
    const ch = value.charAt(index);
    if (ch !== ' ' && ch !== '\n' && ch !== '\r' && ch !== '\t') {
      result += ch;
    }
  }
  return result;
}

function normalizeBase64(value: string): string {
  let result = stripWhitespace(value).split('-').join('+').split('_').join('/');
  const remainder = result.length % 4;
  if (remainder === 2) {
    result += '==';
  } else if (remainder === 3) {
    result += '=';
  }
  return result;
}

function base64Value(ch: string): number {
  return BASE64_ALPHABET.indexOf(ch);
}

function decodeBase64ToBytes(value: string): Array<number> {
  const input = normalizeBase64(value);
  const bytes: Array<number> = [];
  let buffer = 0;
  let bits = 0;

  for (let index = 0; index < input.length; index++) {
    const ch = input.charAt(index);
    if (ch === '=') {
      break;
    }
    const decoded = base64Value(ch);
    if (decoded < 0) {
      throw new Error('Invalid base64 character.');
    }

    buffer = (buffer << 6) | decoded;
    bits += 6;
    while (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 0xFF);
    }
  }
  return bytes;
}

function decodeUtf8(bytes: Array<number>): string {
  let result = '';
  let index = 0;
  while (index < bytes.length) {
    const first = bytes[index];
    if (first < 0x80) {
      result += String.fromCharCode(first);
      index += 1;
    } else if (first >= 0xC0 && first < 0xE0 && index + 1 < bytes.length) {
      const code = ((first & 0x1F) << 6) | (bytes[index + 1] & 0x3F);
      result += String.fromCharCode(code);
      index += 2;
    } else if (first >= 0xE0 && first < 0xF0 && index + 2 < bytes.length) {
      const code = ((first & 0x0F) << 12) | ((bytes[index + 1] & 0x3F) << 6) | (bytes[index + 2] & 0x3F);
      result += String.fromCharCode(code);
      index += 3;
    } else if (first >= 0xF0 && first < 0xF8 && index + 3 < bytes.length) {
      const rawCode = ((first & 0x07) << 18) | ((bytes[index + 1] & 0x3F) << 12) | ((bytes[index + 2] & 0x3F) << 6) | (bytes[index + 3] & 0x3F);
      const code = rawCode - 0x10000;
      result += String.fromCharCode(0xD800 + (code >> 10));
      result += String.fromCharCode(0xDC00 + (code & 0x3FF));
      index += 4;
    } else {
      throw new Error('Invalid UTF-8 byte sequence.');
    }
  }
  return result;
}

function encodeUtf8(value: string): Array<number> {
  const bytes: Array<number> = [];
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6));
      bytes.push(0x80 | (code & 0x3F));
    } else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
      const next = value.charCodeAt(index + 1);
      const full = 0x10000 + (((code & 0x3FF) << 10) | (next & 0x3FF));
      bytes.push(0xF0 | (full >> 18));
      bytes.push(0x80 | ((full >> 12) & 0x3F));
      bytes.push(0x80 | ((full >> 6) & 0x3F));
      bytes.push(0x80 | (full & 0x3F));
      index += 1;
    } else {
      bytes.push(0xE0 | (code >> 12));
      bytes.push(0x80 | ((code >> 6) & 0x3F));
      bytes.push(0x80 | (code & 0x3F));
    }
  }
  return bytes;
}

export function decodeBase64ToUtf8(value: string): string {
  return decodeUtf8(decodeBase64ToBytes(value));
}

export function decodeUtf8Bytes(bytes: Array<number>): string {
  return decodeUtf8(bytes);
}

export function encodeUtf8ToBytes(value: string): Array<number> {
  return encodeUtf8(value);
}

export function encodeUtf8ToBase64(value: string): string {
  const bytes = encodeUtf8(value);
  let result = '';
  let index = 0;
  while (index < bytes.length) {
    const first = bytes[index++];
    const second = index < bytes.length ? bytes[index++] : -1;
    const third = index < bytes.length ? bytes[index++] : -1;

    result += BASE64_ALPHABET.charAt(first >> 2);
    result += BASE64_ALPHABET.charAt(((first & 0x03) << 4) | (second >= 0 ? second >> 4 : 0));
    result += second >= 0 ? BASE64_ALPHABET.charAt(((second & 0x0F) << 2) | (third >= 0 ? third >> 6 : 0)) : '=';
    result += third >= 0 ? BASE64_ALPHABET.charAt(third & 0x3F) : '=';
  }
  return result;
}

export function encodeUtf8ToBase64NoPadding(value: string): string {
  let result = encodeUtf8ToBase64(value);
  while (result.endsWith('=')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
