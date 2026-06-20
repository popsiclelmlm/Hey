const PUNYCODE_BASE: number = 36;
const PUNYCODE_TMIN: number = 1;
const PUNYCODE_TMAX: number = 26;
const PUNYCODE_SKEW: number = 38;
const PUNYCODE_DAMP: number = 700;
const PUNYCODE_INITIAL_BIAS: number = 72;
const PUNYCODE_INITIAL_N: number = 128;

export function toIdnUrl(url: string): string {
  const schemeEnd = url.indexOf('://');
  if (schemeEnd < 0) {
    return url;
  }
  const authorityStart = schemeEnd + 3;
  const authorityEnd = findAuthorityEnd(url, authorityStart);
  const authority = url.substring(authorityStart, authorityEnd);
  if (authority.length === 0) {
    return url;
  }
  const parsed = parseAuthorityHost(authority);
  if (parsed.host.length === 0) {
    return url;
  }
  const asciiHost = toIdnDomain(parsed.host);
  if (asciiHost === parsed.host) {
    return url;
  }
  const nextAuthority = `${authority.substring(0, parsed.hostStart)}${asciiHost}${authority.substring(parsed.hostEnd)}`;
  return `${url.substring(0, authorityStart)}${nextAuthority}${url.substring(authorityEnd)}`;
}

export function toIdnDomain(domain: string): string {
  if (!containsNonAscii(domain)) {
    return domain;
  }
  const labels = normalizeIdnDots(domain).split('.');
  const converted = new Array<string>();
  for (let index = 0; index < labels.length; index++) {
    converted.push(toAsciiLabel(labels[index]));
  }
  return converted.join('.');
}

interface AuthorityHost {
  host: string;
  hostStart: number;
  hostEnd: number;
}

function findAuthorityEnd(url: string, start: number): number {
  let end = url.length;
  const terminators: Array<string> = ['/', '?', '#'];
  for (let index = 0; index < terminators.length; index++) {
    const position = url.indexOf(terminators[index], start);
    if (position >= 0 && position < end) {
      end = position;
    }
  }
  return end;
}

function parseAuthorityHost(authority: string): AuthorityHost {
  const hostStart = authority.lastIndexOf('@') + 1;
  if (hostStart >= authority.length) {
    return { host: '', hostStart, hostEnd: hostStart };
  }
  if (authority.charAt(hostStart) === '[') {
    const bracketEnd = authority.indexOf(']', hostStart + 1);
    if (bracketEnd > hostStart) {
      return {
        host: authority.substring(hostStart + 1, bracketEnd),
        hostStart: hostStart + 1,
        hostEnd: bracketEnd
      };
    }
  }
  let hostEnd = authority.length;
  const colon = authority.lastIndexOf(':');
  if (colon > hostStart && authority.indexOf(':', hostStart) === colon) {
    hostEnd = colon;
  }
  return {
    host: authority.substring(hostStart, hostEnd),
    hostStart,
    hostEnd
  };
}

function toAsciiLabel(label: string): string {
  if (label.length === 0 || !containsNonAscii(label)) {
    return label;
  }
  return `xn--${punycodeEncode(label)}`;
}

function punycodeEncode(label: string): string {
  const codePoints = codePointsFromString(label);
  let output = '';
  let handled = 0;
  for (let index = 0; index < codePoints.length; index++) {
    const value = codePoints[index];
    if (value < 0x80) {
      output += fromCodePoint(value);
      handled++;
    }
  }
  const basicLength = handled;
  if (basicLength > 0 && handled < codePoints.length) {
    output += '-';
  }

  let n = PUNYCODE_INITIAL_N;
  let delta = 0;
  let bias = PUNYCODE_INITIAL_BIAS;
  while (handled < codePoints.length) {
    const m = minCodePointAtLeast(codePoints, n);
    delta += (m - n) * (handled + 1);
    n = m;
    for (let index = 0; index < codePoints.length; index++) {
      const value = codePoints[index];
      if (value < n) {
        delta++;
      } else if (value === n) {
        let q = delta;
        for (let k = PUNYCODE_BASE; ; k += PUNYCODE_BASE) {
          const t = threshold(k, bias);
          if (q < t) {
            break;
          }
          output += encodeDigit(t + ((q - t) % (PUNYCODE_BASE - t)));
          q = Math.floor((q - t) / (PUNYCODE_BASE - t));
        }
        output += encodeDigit(q);
        bias = adapt(delta, handled + 1, handled === basicLength);
        delta = 0;
        handled++;
      }
    }
    delta++;
    n++;
  }
  return output;
}

function adapt(deltaValue: number, points: number, firstTime: boolean): number {
  let delta = firstTime ? Math.floor(deltaValue / PUNYCODE_DAMP) : Math.floor(deltaValue / 2);
  delta += Math.floor(delta / points);
  let k = 0;
  while (delta > Math.floor(((PUNYCODE_BASE - PUNYCODE_TMIN) * PUNYCODE_TMAX) / 2)) {
    delta = Math.floor(delta / (PUNYCODE_BASE - PUNYCODE_TMIN));
    k += PUNYCODE_BASE;
  }
  return k + Math.floor(((PUNYCODE_BASE - PUNYCODE_TMIN + 1) * delta) / (delta + PUNYCODE_SKEW));
}

function threshold(k: number, bias: number): number {
  if (k <= bias) {
    return PUNYCODE_TMIN;
  }
  if (k >= bias + PUNYCODE_TMAX) {
    return PUNYCODE_TMAX;
  }
  return k - bias;
}

function encodeDigit(value: number): string {
  return String.fromCharCode(value < 26 ? 97 + value : 22 + value);
}

function minCodePointAtLeast(values: Array<number>, minimum: number): number {
  let result = 0x7FFFFFFF;
  for (let index = 0; index < values.length; index++) {
    const value = values[index];
    if (value >= minimum && value < result) {
      result = value;
    }
  }
  return result;
}

function codePointsFromString(value: string): Array<number> {
  const result = new Array<number>();
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
      const next = value.charCodeAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        result.push(0x10000 + (((code - 0xD800) << 10) | (next - 0xDC00)));
        index++;
      } else {
        result.push(code);
      }
    } else {
      result.push(code);
    }
  }
  return result;
}

function fromCodePoint(value: number): string {
  if (value <= 0xFFFF) {
    return String.fromCharCode(value);
  }
  const code = value - 0x10000;
  return `${String.fromCharCode(0xD800 + (code >> 10))}${String.fromCharCode(0xDC00 + (code & 0x3FF))}`;
}

function normalizeIdnDots(value: string): string {
  let result = '';
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code === 0x3002 || code === 0xFF0E || code === 0xFF61) {
      result += '.';
    } else {
      result += value.charAt(index);
    }
  }
  return result;
}

function containsNonAscii(value: string): boolean {
  for (let index = 0; index < value.length; index++) {
    if (value.charCodeAt(index) >= 0x80) {
      return true;
    }
  }
  return false;
}
