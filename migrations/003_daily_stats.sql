CREATE TABLE IF NOT EXISTS daily_stats (
  day DATE PRIMARY KEY,
  issued_count INT NOT NULL,
  claimed_count INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
