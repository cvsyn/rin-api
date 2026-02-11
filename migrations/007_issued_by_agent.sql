ALTER TABLE entities ADD COLUMN IF NOT EXISTS issued_by_agent_name TEXT;

ALTER TABLE entities
  ADD CONSTRAINT IF NOT EXISTS fk_entities_issued_by_agent
  FOREIGN KEY (issued_by_agent_name) REFERENCES agents(name) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_entities_issued_by_agent_name ON entities(issued_by_agent_name);
