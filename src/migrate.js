import fs from 'node:fs';
import path from 'node:path';
import { query, closePool } from './db.js';

const MIGRATIONS_DIR = path.join(process.cwd(), 'migrations');

async function ensureSchemaTable() {
  await query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id SERIAL PRIMARY KEY,
      filename TEXT NOT NULL UNIQUE,
      applied_at TIMESTAMPTZ NOT NULL
    );
  `);
}

async function getAppliedMigrations() {
  const result = await query('SELECT filename FROM schema_migrations ORDER BY id');
  return new Set(result.rows.map((row) => row.filename));
}

async function applyMigration(file) {
  const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
  await query('BEGIN');
  try {
    await query(sql);
    await query('INSERT INTO schema_migrations (filename, applied_at) VALUES ($1, NOW())', [file]);
    await query('COMMIT');
  } catch (err) {
    await query('ROLLBACK');
    throw err;
  }
}

async function run() {
  await ensureSchemaTable();
  const applied = await getAppliedMigrations();

  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((file) => file.endsWith('.sql'))
    .sort();

  for (const file of files) {
    if (applied.has(file)) continue;
    await applyMigration(file);
    console.log(`Applied ${file}`);
  }
}

run()
  .then(() => closePool())
  .catch(async (err) => {
    console.error('Migration failed');
    console.error(err);
    await closePool();
    process.exit(1);
  });
