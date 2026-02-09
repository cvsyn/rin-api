ALTER TABLE public.entities
  ADD COLUMN IF NOT EXISTS claim_token_hash TEXT,
  ADD COLUMN IF NOT EXISTS claim_token_issued_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_entities_claim_token_hash
  ON public.entities (claim_token_hash);
