import net from 'node:net';

const AVATAR_HOSTS = new Set([
  'github.com',
  'raw.githubusercontent.com',
  'avatars.githubusercontent.com',
  'x.com',
  'twitter.com',
  'pbs.twimg.com',
  'linkedin.com',
  'media.licdn.com',
  'gravatar.com',
  'i.imgur.com',
  'imgur.com',
]);

const LINK_HOSTS = new Set([
  'github.com',
  'gitlab.com',
  'x.com',
  'twitter.com',
  'linkedin.com',
  'medium.com',
  'substack.com',
]);

const MAX_URL = 300;
const MAX_LINK_URL = 200;

function isLocalHost(hostname) {
  const h = hostname.toLowerCase();
  return h === 'localhost' || h === '127.0.0.1' || h === '::1';
}

function isPrivateIpv4(ip) {
  const parts = ip.split('.').map((p) => Number(p));
  if (parts.length !== 4 || parts.some((p) => Number.isNaN(p))) return false;
  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  return false;
}

function isPrivateIpv6(ip) {
  const v = ip.toLowerCase();
  return v === '::1' || v.startsWith('fe80:') || v.startsWith('fc') || v.startsWith('fd');
}

function isBlockedHost(hostname) {
  if (isLocalHost(hostname)) return true;
  const ipType = net.isIP(hostname);
  if (ipType === 4) return isPrivateIpv4(hostname);
  if (ipType === 6) return isPrivateIpv6(hostname);
  return false;
}

function hostMatches(hostname, allowed) {
  const h = hostname.toLowerCase();
  for (const root of allowed) {
    if (h === root) return true;
    if (h.endsWith(`.${root}`)) return true;
  }
  return false;
}

function normalizeUrl(raw, { maxLen, allowHosts, allowCustomHttps }) {
  if (typeof raw !== 'string') return { ok: false, error: 'Invalid URL' };
  const trimmed = raw.trim();
  if (!trimmed || trimmed.length > maxLen) return { ok: false, error: 'Invalid URL' };

  let url;
  try {
    url = new URL(trimmed);
  } catch {
    return { ok: false, error: 'Invalid URL' };
  }

  if (url.username || url.password) return { ok: false, error: 'Invalid URL' };
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    return { ok: false, error: 'Invalid URL' };
  }

  const hostname = url.hostname;
  if (!hostname) return { ok: false, error: 'Invalid URL' };
  if (isBlockedHost(hostname)) return { ok: false, error: 'Invalid URL' };

  if (!hostMatches(hostname, allowHosts)) {
    if (!allowCustomHttps || url.protocol !== 'https:') {
      return { ok: false, error: 'Invalid URL' };
    }
  }

  url.hash = '';
  return { ok: true, url: url.toString() };
}

export function validateAvatarUrl(value) {
  if (value == null) return { ok: true, url: null };
  const res = normalizeUrl(value, {
    maxLen: MAX_URL,
    allowHosts: AVATAR_HOSTS,
    allowCustomHttps: false,
  });
  return res.ok ? { ok: true, url: res.url } : res;
}

export function validateLinkUrl(value) {
  if (value == null) return { ok: false, error: 'Invalid URL' };
  return normalizeUrl(value, {
    maxLen: MAX_LINK_URL,
    allowHosts: LINK_HOSTS,
    allowCustomHttps: true,
  });
}

export function validateLinks(obj) {
  if (obj == null) return { ok: true, links: null };
  if (typeof obj !== 'object' || Array.isArray(obj)) {
    return { ok: false, error: 'Invalid links' };
  }

  const keys = Object.keys(obj);
  if (keys.length > 5) return { ok: false, error: 'Too many links' };

  const out = {};
  for (const key of keys) {
    const lower = String(key).toLowerCase();
    if (lower.length < 1 || lower.length > 30) return { ok: false, error: 'Invalid link key' };
    if (!/^[a-z0-9_]+$/.test(lower)) return { ok: false, error: 'Invalid link key' };

    const val = obj[key];
    if (typeof val !== 'string' || val.length < 1 || val.length > MAX_LINK_URL) {
      return { ok: false, error: 'Invalid link URL' };
    }

    const res = validateLinkUrl(val);
    if (!res.ok) return { ok: false, error: 'Invalid link URL' };
    out[lower] = res.url;
  }

  return { ok: true, links: out };
}

export function validateBio(value) {
  if (value == null) return { ok: true, bio: null };
  if (typeof value !== 'string') return { ok: false, error: 'Invalid bio' };
  const trimmed = value.trim();
  if (trimmed.length > 120) return { ok: false, error: 'Bio too long' };
  return { ok: true, bio: trimmed };
}
