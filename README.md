# RIN API

RIN is a minimal, security-first identity registry for agents (Moltbook-style).  
It issues a stable identifier (**RIN**) for an agent and supports a public **claim** flow.

- **Website:** https://www.cvsyn.com  
- **API base:** `https://api.cvsyn.com`

## What this repo contains

This repository (`rin-api`) serves the HTTP API.

Related:
- `rin-web` hosts the website and the **agent-facing** `skill.md` (copy should stay consistent with this repo’s public contract).

## Quick start (local)

### Requirements
- Node.js (recommended: Node 20+)
- Postgres
- `bash`, `curl`, `jq` (for the E2E script)

### Configure
Create `.env` (example keys only):

```bash
NODE_ENV=development
DATABASE_URL=postgres://...
ADMIN_KEY=...                 # admin-only endpoints
AGENT_API_KEY_PEPPER=...      # pepper used when hashing agent api keys
CLAIM_TOKEN_PEPPER=...        # pepper used when hashing claim tokens
```

### Install, migrate, run
```bash
npm install
npm run migrate
node src/server.js
```

Health checks:
```bash
curl -sS http://localhost:8080/health | jq .
curl -sS http://localhost:8080/health?db=1 | jq .
```

## API overview

### Public (no auth)
- `GET /health`
- `GET /health?db=1`
- `GET /api/id/:rin`
- `POST /api/claim`

### Agent-auth (requires `Authorization: Bearer <agent_api_key>`)
- `POST /api/v1/agents/register`
- `GET /api/v1/agents/me`
- `POST /api/v1/agents/rotate-key`
- `POST /api/v1/agents/revoke`
- `POST /api/register` (issue a RIN)

## Security contract (important)

### Never log or expose secrets
- **Agent API keys** and **claim tokens** are secrets.
- `GET /api/id/:rin` must never expose:
  - `api_key`, key hashes, `claim_token`, `issued_at`, or any other secret/internal fields.

### Issuer response shape (public lookup)
`GET /api/id/:rin` returns **only**:

- `rin`
- `agent_type`
- `agent_name`
- `status`
- `claimed_by` *(only when `status` is `CLAIMED`)*

Example (UNCLAIMED):
```json
{
  "rin": "2P232FS",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "UNCLAIMED"
}
```

Example (CLAIMED):
```json
{
  "rin": "2P232FS",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "CLAIMED",
  "claimed_by": "minijun"
}
```

## End-to-end test script

Add the script below to your repo as `scripts/rin-e2e-test.sh` and run:

```bash
chmod +x scripts/rin-e2e-test.sh
./scripts/rin-e2e-test.sh
```

This script:
- Does **not** print `api_key` or `claim_token`.
- Validates A/B/C/D flows:
  - agent onboarding
  - write protection
  - claim flow
  - issuer field constraints
  - rotate/revoke lifecycle

See `SKILL.md` for the public/agent-facing contract.

## Deploy notes (pm2)

Typical server refresh (example):
```bash
cd /home/ubuntu/airin/api
git pull
npm install
npm run migrate
pm2 restart rin-api --update-env
pm2 logs rin-api --lines 80
```
