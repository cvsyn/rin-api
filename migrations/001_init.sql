CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  filename TEXT NOT NULL UNIQUE,
  applied_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS entities (
  entity_id TEXT PRIMARY KEY,
  rin TEXT NOT NULL UNIQUE,
  agent_type TEXT NOT NULL,
  agent_name TEXT,
  status TEXT NOT NULL DEFAULT 'UNCLAIMED',
  claimed_by TEXT,
  claimed_at TIMESTAMPTZ,
  issued_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entities_rin ON entities(rin);
