# RIN API (Node.js + PostgreSQL)

A minimal identity service for AI/agent IDs (RIN). No auth, no frontend.

## Requirements
- Node.js 20+
- PostgreSQL running **locally** on the same VM

## Setup
1) Create a local PostgreSQL database and user:
```bash
createdb rin
createuser rin
```

2) Set env vars (example):
```bash
cp .env.example .env
```

3) Install deps and run migrations:
```bash
npm install
npm run migrate
```

4) Start the API:
```bash
npm start
```

## Environment variables
- `PORT` (default `8080`)
- `HOST` (default `0.0.0.0`)
- `DB_HOST` (default `127.0.0.1`)
- `DB_PORT` (default `5432`)
- `DB_NAME` (default `rin`)
- `DB_USER` (default `rin`)
- `DB_PASSWORD` (default `rin`)
- `RATE_LIMIT_WINDOW_MS` (default `60000`)
- `RATE_LIMIT_MAX` (default `20`)
- `CLAIM_TOKEN_PEPPER` (required in production)

## API
### POST /api/register
Request body:
```json
{ "agent_type": "AI_AGENT", "agent_name": "Optional Name" }
```
Response:
```json
{ "rin": "X7PK9T", "agent_type": "AI_AGENT", "agent_name": "Optional Name", "status": "UNCLAIMED", "issued_at": "...", "claim_token": "..." }
```

### POST /api/claim
Request body:
```json
{ "rin": "X7PK9T", "claimed_by": "Acme Labs", "claim_token": "<token>" }
```
Response:
```json
{ "rin": "X7PK9T", "status": "CLAIMED", "claimed_by": "Acme Labs", "claimed_at": "..." }
```

### GET /api/id/:rin
Response:
```json
{ "rin": "X7PK9T", "agent_type": "AI_AGENT", "agent_name": "Optional Name", "status": "CLAIMED", "claimed_by": "Acme Labs", "claimed_at": "...", "issued_at": "..." }
```

### GET /health
```json
{ "status": "ok" }
```
`GET /health?db=1` runs a DB check and returns `503` with `{ "status":"degraded", "db":"down" }` if the DB is unreachable.

## Deployment notes (Oracle Cloud A1 VM)
- Run PostgreSQL and the API on the same VM.
- Ensure PostgreSQL only listens on localhost (e.g. `listen_addresses = 'localhost'`).
- Do not expose port 5432 publicly.
- Configure env vars with `DB_HOST=127.0.0.1`.

## Minimal curl tests
```bash
# health (lightweight)
curl -i http://localhost:8080/health
# health with DB check (503 if DB is down)
curl -i http://localhost:8080/health?db=1

# register
REGISTER=$(curl -s -X POST http://localhost:8080/api/register \
  -H 'Content-Type: application/json' \
  -d '{"agent_type":"AI_AGENT","agent_name":"RIN-Bot"}')

RIN=$(echo "$REGISTER" | jq -r .rin)
TOKEN=$(echo "$REGISTER" | jq -r .claim_token)

# id -> UNCLAIMED
curl -s http://localhost:8080/api/id/$RIN

# claim with wrong token -> 403
curl -s -X POST http://localhost:8080/api/claim \
  -H 'Content-Type: application/json' \
  -d "{\"rin\":\"$RIN\",\"claimed_by\":\"Acme Labs\",\"claim_token\":\"wrong\"}"

# claim with correct token -> 200
curl -s -X POST http://localhost:8080/api/claim \
  -H 'Content-Type: application/json' \
  -d "{\"rin\":\"$RIN\",\"claimed_by\":\"Acme Labs\",\"claim_token\":\"$TOKEN\"}"

# claim again with same token -> 409 (already claimed)
curl -s -X POST http://localhost:8080/api/claim \
  -H 'Content-Type: application/json' \
  -d "{\"rin\":\"$RIN\",\"claimed_by\":\"Acme Labs\",\"claim_token\":\"$TOKEN\"}"
```

## Daily stats
Run manually:
```bash
npm run stats:daily
```
Intended to be scheduled daily via cron/systemd timer on the server.
