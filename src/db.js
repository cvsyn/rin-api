import { Pool } from 'pg';

const pool = new Pool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || 'rin',
  user: process.env.DB_USER || 'rin',
  password: process.env.DB_PASSWORD || 'rin',
});

export function query(text, params) {
  return pool.query(text, params);
}

export async function closePool() {
  await pool.end();
}
