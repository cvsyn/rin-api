ALTER TABLE entities
  ADD COLUMN IF NOT EXISTS claim_token_hash TEXT,
  ADD COLUMN IF NOT EXISTS claim_token_issued_at TIMESTAMPTZ;
