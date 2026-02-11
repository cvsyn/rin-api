# RIN — Skill / API Contract (rin-api)

This document describes the public contract for the **RIN API**.

- **API base:** `https://api.cvsyn.com`
- **Purpose:** minimal identity registry for agents + human claim flow (security-first).

---

## Endpoints

### Public (no auth required)

- `GET /health`
- `GET /health?db=1`
- `GET /api/id/:rin`
- `POST /api/claim`

### Agent-auth (requires `Authorization: Bearer <agent_api_key>`)

- `POST /api/v1/agents/register`
- `GET /api/v1/agents/me`
- `POST /api/v1/agents/rotate-key`
- `POST /api/v1/agents/revoke`
- `POST /api/register` *(issue a RIN + claim token)*

---

## Authentication

Agent-auth endpoints require:

```
Authorization: Bearer rin_...
```

Only send this header to **`https://api.cvsyn.com`**.

---

## Response contracts

### 1) Register an agent key

`POST /api/v1/agents/register`

Body:
```json
{ "name": "my-agent", "description": "optional" }
```

Response (secret returned once):
```json
{
  "agent": {
    "name": "my-agent",
    "description": "optional",
    "api_key": "rin_...",
    "created_at": "..."
  },
  "important": "SAVE YOUR API KEY!"
}
```

### 2) Agent “me”

`GET /api/v1/agents/me` (auth required)

Response:
```json
{
  "name": "my-agent",
  "description": "optional",
  "created_at": "...",
  "last_seen_at": "...",
  "revoked_at": null
}
```

### 3) Rotate agent key

`POST /api/v1/agents/rotate-key` (auth required)

Response:
```json
{
  "api_key": "rin_...NEW...",
  "rotated": true,
  "important": "SAVE YOUR API KEY!"
}
```

Expected behavior:
- old key → **401**
- new key → **200** (for `/api/v1/agents/me`)

### 4) Revoke agent key

`POST /api/v1/agents/revoke` (auth required)

Response:
```json
{ "revoked": true }
```

Expected behavior:
- revoked key → **401** (for `/api/v1/agents/me`)

---

## RIN issuance + claim

### 5) Issue a RIN (write-protected)

`POST /api/register` (auth required)

Body:
```json
{ "agent_type": "openclaw", "agent_name": "prod" }
```

Response (contains one-time secret `claim_token`):
```json
{
  "rin": "2P232FS",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "UNCLAIMED",
  "claim_token": "..."
}
```

### 6) Claim a RIN (public)

`POST /api/claim`

Body:
```json
{ "rin": "2P232FS", "claimed_by": "alice", "claim_token": "..." }
```

Response:
```json
{ "rin": "2P232FS", "status": "CLAIMED", "claimed_by": "alice" }
```

---

## Issuer visibility rules (critical)

`GET /api/id/:rin` is public and must expose **only**:

- `rin`
- `agent_type`
- `agent_name`
- `status`
- `claimed_by` *(only when claimed)*

It must **never** include:
- `api_key`, key hashes, `claim_token`, `issued_at`, or other internal fields.

---

## E2E verification

Use `scripts/rin-e2e-test.sh` (see README) to validate:

- register agent → `me` (200)
- rotate → old key 401, new key 200
- revoke → new key 401
- `/api/register` without auth → 401
- claim flow + issuer field constraints
