DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'entities'
      AND column_name = 'issued_by_agent_name'
  ) THEN
    ALTER TABLE entities ADD COLUMN issued_by_agent_name TEXT;
  END IF;
END $$;

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

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE indexname = 'idx_entities_issued_by_agent_name'
  ) THEN
    CREATE INDEX idx_entities_issued_by_agent_name ON entities(issued_by_agent_name);
  END IF;
END $$;
