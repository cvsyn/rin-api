import 'dotenv/config';
import { query, closePool } from '../db.js';

function getUtcDayRange(date) {
  const start = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return { start, end };
}

async function run() {
  const now = new Date();
  const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const { start, end } = getUtcDayRange(yesterday);
  const dayStr = start.toISOString().slice(0, 10);

  const registerResult = await query(
    `SELECT COUNT(*)::bigint AS count
     FROM entities
     WHERE issued_at >= $1 AND issued_at < $2`,
    [start.toISOString(), end.toISOString()]
  );

  const claimResult = await query(
    `SELECT COUNT(*)::bigint AS count
     FROM entities
     WHERE claimed_at >= $1 AND claimed_at < $2`,
    [start.toISOString(), end.toISOString()]
  );

  const registerCount = Number(registerResult.rows[0]?.count || 0);
  const claimCount = Number(claimResult.rows[0]?.count || 0);

  await query(
    `INSERT INTO daily_stats (day, register_count, claim_count)
     VALUES ($1, $2, $3)
     ON CONFLICT (day) DO UPDATE
     SET register_count = EXCLUDED.register_count,
         claim_count = EXCLUDED.claim_count`,
    [dayStr, registerCount, claimCount]
  );

  console.log(`daily_stats ok day=${dayStr} register=${registerCount} claim=${claimCount}`);
}

run()
  .then(() => closePool())
  .then(() => process.exit(0))
  .catch(async () => {
    console.error('daily_stats failed');
    await closePool();
    process.exit(1);
  });
