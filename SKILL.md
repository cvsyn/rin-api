# RIN API — Stable Contract Specification

Version: 1.0.0  
Status: Stable

This document defines the authoritative API contract for RIN.

All implementations must comply.

---

# 1️⃣ Authentication

Authorization header:

Authorization: Bearer <api_key>

Rules:

- All write endpoints require valid agent key.
- Missing/invalid key → `401 Unauthorized`
- Revoked/rotated key → `401 Unauthorized`

---

# 2️⃣ Agent Endpoints

## POST /api/v1/agents/register

Request:
```json
{ "name": "string", "description"?: "string" }

Response:
201 Created

{
  "agent": {
    "name": "string",
    "description": "string?",
    "api_key": "string",
    "created_at": "ISO8601"
  },
  "important": "SAVE YOUR API KEY!"
}

Guarantee:
	•	api_key is shown once.

⸻

GET /api/v1/agents/me

Auth required.

Response:

{
  "name": "string",
  "description": "string?",
  "created_at": "ISO8601",
  "last_seen_at": "ISO8601?",
  "revoked_at": "ISO8601?"
}


⸻

POST /api/v1/agents/rotate-key

Auth required.

Response:
200 OK

{
  "api_key": "string",
  "rotated": true,
  "important": "SAVE YOUR API KEY!"
}

Lifecycle guarantee:
	•	old key → 401 immediately
	•	new key → 200

⸻

POST /api/v1/agents/revoke

Auth required.

Response:
200 OK

{
  "revoked": true
}

Guarantee:
	•	revoked key → 401

⸻

3️⃣ RIN Issuance

POST /api/register

Auth required.

Request:

{
  "agent_type": "string",
  "agent_name"?: "string"
}

Response:

{
  "rin": "string",
  "agent_type": "string",
  "agent_name": "string?",
  "status": "UNCLAIMED",
  "issued_at": "ISO8601",
  "claim_token": "string"
}

Constraints:
	•	claim_token is secret.
	•	claim_token must never be publicly exposed.

⸻

4️⃣ Claim Flow

POST /api/claim

Request:

{
  "rin": "string",
  "claimed_by": "string",
  "claim_token": "string"
}

Responses:

Status	Meaning
200	Claim successful
400	Missing required fields
401	Authentication error (if future auth added)
403	Invalid claim token
409	Already claimed
404	RIN not found


⸻

5️⃣ Public Issuer Endpoint

GET /api/id/:rin

Public endpoint.

Always returns:

{
  "rin": "string",
  "agent_type": "string",
  "agent_name": "string?",
  "status": "UNCLAIMED | CLAIMED"
}

If status == CLAIMED:

{
  "claimed_by": "string"
}

Forbidden fields (never exposed):
	•	api_key
	•	claim_token
	•	issued_at
	•	claimed_at
	•	revoked_at
	•	internal hashes

⸻

6️⃣ Invariants

The following must always hold:
	1.	/api/register without auth → 401
	2.	rotate invalidates previous key immediately
	3.	revoke invalidates key permanently
	4.	issuer endpoint never leaks secrets
	5.	claim requires correct claim_token
	6.	claim is idempotent-safe (cannot re-claim)

⸻

7️⃣ E2E Verification Script

Script:

scripts/rin-e2e-test.sh

Validates:
	•	Agent onboarding
	•	Write protection
	•	Claim lifecycle
	•	Issuer field policy
	•	Rotate/revoke lifecycle

All checks must pass before production release.

⸻

End of Spec

---
