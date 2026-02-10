# RIN API (Node.js + PostgreSQL)

A minimal identity service for AI/agent IDs (RIN) with agent API key auth for write/admin endpoints.

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
- `ADMIN_KEY` (required in production)
- `AGENT_API_KEY_PEPPER` (required in production)

## API
### Agent auth (Moltbook-style)
1) Register an agent to receive an API key (returned once).
2) Use `Authorization: Bearer rin_...` for write/admin endpoints.
3) Store the key securely and rotate/revoke when needed.

### POST /api/v1/agents/register
Request body:
```json
{ "name": "openclaw", "description": "..." }
```
Response:
```json
{ "agent": { "name": "openclaw", "description": "...", "api_key": "rin_...", "created_at": "..." }, "important": "SAVE YOUR API KEY!" }
```

### GET /api/v1/agents/me
Header:
```
Authorization: Bearer <api_key>
```
Response:
```json
{ "name": "openclaw", "description": "...", "created_at": "...", "last_seen_at": "...", "revoked_at": null }
```

### POST /api/v1/agents/rotate-key
Header:
```
Authorization: Bearer <api_key>
```
Response:
```json
{ "api_key": "rin_...", "rotated": true, "important": "SAVE YOUR API KEY!" }
```

### POST /api/v1/agents/revoke
Header:
```
Authorization: Bearer <api_key>
```
Response:
```json
{ "revoked": true }
```

### GET /api/v1/agents/status
Header:
```
Authorization: Bearer <api_key>
```
Response:
```json
{ "status": "active" }
```

### POST /api/register
Request body:
```json
{ "agent_type": "AI_AGENT", "agent_name": "Optional Name" }
```
Header:
```
Authorization: Bearer <api_key>
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
Header:
```
Authorization: Bearer <api_key>
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

### GET /admin/stats
Header:
```
X-Admin-Key: <ADMIN_KEY>
Authorization: Bearer <api_key>
```
Response:
```json
{
  "range_days": 30,
  "daily": [{ "day": "YYYY-MM-DD", "register_count": 0, "claim_count": 0 }],
  "totals": { "register_count": 0, "claim_count": 0 }
}
```

Example:
```bash
curl -sS -H "X-Admin-Key: <key>" -H "Authorization: Bearer <api_key>" https://api.cvsyn.com/admin/stats | jq .
```

## Deployment notes (Oracle Cloud A1 VM)
- Run PostgreSQL and the API on the same VM.
- Ensure PostgreSQL only listens on localhost (e.g. `listen_addresses = 'localhost'`).
- Do not expose port 5432 publicly.
- Configure env vars with `DB_HOST=127.0.0.1`.

## Minimal curl tests
```bash
# agent register -> api_key
AGENT=$(curl -s -X POST http://localhost:8080/api/v1/agents/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"openclaw","description":"test agent"}')

API_KEY=$(echo "$AGENT" | jq -r .agent.api_key)

# health (lightweight)
curl -i http://localhost:8080/health
# health with DB check (503 if DB is down)
curl -i http://localhost:8080/health?db=1

# register
REGISTER=$(curl -s -X POST http://localhost:8080/api/register \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"agent_type":"AI_AGENT","agent_name":"RIN-Bot"}')

RIN=$(echo "$REGISTER" | jq -r .rin)
TOKEN=$(echo "$REGISTER" | jq -r .claim_token)

# id -> UNCLAIMED
curl -s http://localhost:8080/api/id/$RIN

# claim with wrong token -> 403
curl -s -X POST http://localhost:8080/api/claim \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{\"rin\":\"$RIN\",\"claimed_by\":\"Acme Labs\",\"claim_token\":\"wrong\"}"

# claim with correct token -> 200
curl -s -X POST http://localhost:8080/api/claim \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{\"rin\":\"$RIN\",\"claimed_by\":\"Acme Labs\",\"claim_token\":\"$TOKEN\"}"

# claim again with same token -> 409 (already claimed)
curl -s -X POST http://localhost:8080/api/claim \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{\"rin\":\"$RIN\",\"claimed_by\":\"Acme Labs\",\"claim_token\":\"$TOKEN\"}"

# rotate -> old key unauthorized, new key ok
ROTATE=$(curl -s -X POST http://localhost:8080/api/v1/agents/rotate-key \
  -H "Authorization: Bearer $API_KEY")
NEW_KEY=$(echo "$ROTATE" | jq -r .api_key)
curl -s -o /dev/null -w "%{http_code}\\n" -X POST http://localhost:8080/api/register \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"agent_type":"AI_AGENT"}'
curl -s -o /dev/null -w "%{http_code}\\n" -X POST http://localhost:8080/api/register \
  -H "Authorization: Bearer $NEW_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"agent_type":"AI_AGENT"}'

# revoke -> unauthorized afterwards
curl -s -X POST http://localhost:8080/api/v1/agents/revoke \
  -H "Authorization: Bearer $NEW_KEY"
curl -s -o /dev/null -w "%{http_code}\\n" -X POST http://localhost:8080/api/register \
  -H "Authorization: Bearer $NEW_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"agent_type":"AI_AGENT"}'
```

## Daily stats
Run manually:
```bash
npm run stats:daily
```
Intended to be scheduled daily via cron/systemd timer on the server.

## CLI usage
Store credentials at `~/.config/rin/credentials.json` (0600). Never share API keys.
```bash
node rin-cli.mjs me
node rin-cli.mjs rotate
node rin-cli.mjs revoke
```
