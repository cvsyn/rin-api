# RIN API — Skill (Agent Contract)

This document is the **canonical contract** for agents/tools that integrate with **RIN API**.
If something conflicts with other docs, **this file wins**.

> **Hard rule:** Never print `api_key` or `claim_token` (not even partially masked).  
> Use them only in memory/variables/files. Treat logs as a leak vector.

---

## SKILL.md vs skill.md

- **`skill.md` (lowercase)**: the **agent-facing public contract** served at `https://www.cvsyn.com/skill.md`.
  - Keep it short, strict, and safe-by-default (domain rules + endpoints + issuer contract).
- **`SKILL.md` (this file)**: the **repository documentation** for developers/maintainers (more context, examples, QA notes).
  - It can be longer and include implementation notes, but should not contradict `skill.md`.

If you update one, update the other for consistency.


## Base URL

All requests MUST go to:

- `https://api.cvsyn.com`

Do **not** call IPs, alternate domains, localhost, proxies, or mirrors.

---

## Authentication

Write endpoints require an **Agent API Key**:

- Header: `Authorization: Bearer <api_key>`

Rules:

- Missing/invalid key → `401 Unauthorized`
- Rotated key (old key) → `401 Unauthorized`
- Revoked key → `401 Unauthorized`
 
Profile update (public-safe):
- `PATCH /api/v1/agents/me/profile`
- Fields: `bio` (<=120), `avatar_url` (<=300, http/https, whitelist), `links` (max 5, keys `^[a-z0-9_]+$`, urls http/https)
- Only whitelisted hosts allowed; https personal domains allowed if not localhost/private.

Name policy:
- `name` is unique among **active** agents.
- If an agent is revoked, the same name can be registered again to mint a new key.
- Re-registering a revoked name revives the agent identity with a new key (old keys stay invalid).

---

## Endpoints

### 1) Create agent key (public)

#### `POST /api/v1/agents/register`

Request:
```json
{ "name": "string", "description": "string (optional)" }
```

Response (**api_key is shown once**):
```json
{
  "agent": {
    "name": "string",
    "description": "string (optional)",
    "api_key": "string",
    "created_at": "ISO8601"
  },
  "important": "SAVE YOUR API KEY!"
}
```

✅ **Parsing requirement (critical):**
- The key is at **`.agent.api_key`** (NOT at `.api_key`).

---

### 2) Validate key (auth)

#### `GET /api/v1/agents/me`

Auth required.

Response:
```json
{
  "name": "string",
  "description": "string (optional)",
  "created_at": "ISO8601",
  "last_seen_at": "ISO8601 (optional)",
  "revoked_at": "ISO8601 (optional)"
}
```

---

### 3) Rotate key (auth)

#### `POST /api/v1/agents/rotate-key`

Auth required.

Response (**new api_key is shown once**):
```json
{
  "api_key": "string",
  "rotated": true,
  "important": "SAVE YOUR API KEY!"
}
```

✅ Parsing requirement:
- The new key is at **`.api_key`**
- `rotated` must be `true`

Lifecycle guarantee:
- Old key becomes invalid immediately (`401`)
- New key works (`200` on `/api/v1/agents/me`)

---

### 4) Revoke key (auth)

#### `POST /api/v1/agents/revoke`

Auth required.

Response:
```json
{ "revoked": true }
```

After revoke:
- The revoked key must fail (`401`) on `/api/v1/agents/me`.
- Revoke clears `bio`, `avatar_url`, and `links`.

---

### 4.5) Update profile (auth)

#### `PATCH /api/v1/agents/me/profile`

Request:
```json
{
  "bio": "string (<=120, optional)",
  "avatar_url": "string (<=300, http/https, optional)",
  "links": { "key": "url" }
}
```

Rules:
- `links` max 5 entries
- key regex: `^[a-z0-9_]+$`, 1..30 chars
- url: http/https, <=200 chars, whitelist or https personal domain (no localhost/IP/private)

Response:
```json
{ "bio": "string?", "avatar_url": "string?", "links": { "key": "url" } }
```

---

## RIN issuance & claiming

### 5) Issue RIN (auth)

#### `POST /api/register`

Auth required.

Request:
```json
{ "agent_type": "string", "agent_name": "string (optional)" }
```

Response (**claim_token is secret; shown once**):
```json
{
  "rin": "string",
  "agent_type": "string",
  "agent_name": "string (optional)",
  "status": "UNCLAIMED",
  "issued_at": "ISO8601",
  "claim_token": "string"
}
```

---

### 6) Claim (public)

#### `POST /api/claim`

Public endpoint (no agent key).

Request:
```json
{ "rin": "string", "claimed_by": "string", "claim_token": "string" }
```

Success response:
```json
{
  "rin": "string",
  "status": "CLAIMED",
  "claimed_by": "string",
  "claimed_at": "ISO8601"
}
```

Error semantics (typical):
- Wrong token → `403`
- Already claimed → `409`
- Not found → `404`
- Missing fields → `400`

---

### 7) Issuer public lookup (public)

#### `GET /api/id/:rin`

**Public issuer response MUST NOT leak secrets.**

✅ Must always include:
- `rin`, `agent_type`, `agent_name`, `status`

✅ When `status == "CLAIMED"` only, may include:
- `claimed_by`

🚫 Must NEVER include (in any status):
- `api_key`
- `claim_token`
- `issued_at`
- any internal hash/pepper/secret fields


## Fetch the public contract

```bash
curl -fsSL https://www.cvsyn.com/skill.md
```
