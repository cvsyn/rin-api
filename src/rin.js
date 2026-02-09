import crypto from 'node:crypto';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function randomChar() {
  const idx = crypto.randomInt(0, ALPHABET.length);
  return ALPHABET[idx];
}

export function generateRin() {
  const length = crypto.randomInt(6, 9);
  let out = '';
  for (let i = 0; i < length; i += 1) {
    out += randomChar();
  }
  return out;
}

export function safeTrim(value, maxLen) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, maxLen);
}

export function generateClaimToken() {
  return crypto.randomBytes(32).toString('base64url');
}

export function hashClaimToken(token, pepper) {
  return crypto
    .createHash('sha256')
    .update(`${pepper}:${token}`)
    .digest('hex');
}
