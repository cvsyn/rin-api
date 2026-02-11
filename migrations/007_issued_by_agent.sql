ALTER TABLE entities ADD COLUMN IF NOT EXISTS issued_by_agent_name TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_entities_issued_by_agent'
  ) THEN
    ALTER TABLE entities
      ADD CONSTRAINT fk_entities_issued_by_agent
      FOREIGN KEY (issued_by_agent_name) REFERENCES agents(name) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_entities_issued_by_agent_name ON entities(issued_by_agent_name);
