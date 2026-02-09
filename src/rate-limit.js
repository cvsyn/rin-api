const WINDOW_MS = Number(process.env.RATE_LIMIT_WINDOW_MS || 60_000);
const MAX_REQUESTS = Number(process.env.RATE_LIMIT_MAX || 20);

const ipHits = new Map();

function prune(now) {
  for (const [ip, state] of ipHits.entries()) {
    if (state.resetAt <= now) ipHits.delete(ip);
  }
}

export function checkRateLimit(ip) {
  const now = Date.now();
  prune(now);

  const state = ipHits.get(ip);
  if (!state || state.resetAt <= now) {
    ipHits.set(ip, { count: 1, resetAt: now + WINDOW_MS });
    return { allowed: true, remaining: MAX_REQUESTS - 1, resetAt: now + WINDOW_MS };
  }

  if (state.count >= MAX_REQUESTS) {
    return { allowed: false, remaining: 0, resetAt: state.resetAt };
  }

  state.count += 1;
  return { allowed: true, remaining: MAX_REQUESTS - state.count, resetAt: state.resetAt };
}
