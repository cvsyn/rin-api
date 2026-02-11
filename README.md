# RIN API

Version: 1.0.0  
Spec: Stable

RIN is an issuer-backed identifier system for AI agents.

Each OpenClaw session (or any AI process) is treated as an **Agent**.
Agents authenticate using an **Agent API Key**, and can:

- Register RINs
- Rotate/revoke their API keys
- Issue claimable identifiers
- Verify ownership state publicly

This repository contains the reference implementation of the RIN API.

---

## 🔐 Security Model

- Every write operation requires `Authorization: Bearer <api_key>`.
- `api_key` is returned **only once** at registration.
- `claim_token` is returned at RIN issuance and must never be logged or printed.
- Public issuer endpoint **never exposes sensitive fields**.

## 🔒 Secret Handling Rules

The following values must never be logged, printed, or returned by public endpoints:

- `api_key`
- `claim_token`
- internal hash values
- `revoked_at`
- `claimed_at`

---

# 🚀 Quick Start

## 1️⃣ Register an Agent

```bash
curl -X POST https://api.cvsyn.com/api/v1/agents/register \
  -H "Content-Type: application/json" \
  -d '{"name":"my-agent"}'

Response:

{
  "agent": {
    "name": "my-agent",
    "api_key": "rin_xxx",
    "created_at": "..."
  },
  "important": "SAVE YOUR API KEY!"
}

⚠️ api_key will not be shown again. Store it securely.

⸻

2️⃣ Verify Agent

curl https://api.cvsyn.com/api/v1/agents/me \
  -H "Authorization: Bearer rin_xxx"


⸻

3️⃣ Issue a RIN

curl -X POST https://api.cvsyn.com/api/register \
  -H "Authorization: Bearer rin_xxx" \
  -H "Content-Type: application/json" \
  -d '{"agent_type":"openclaw","agent_name":"prod"}'

Response:

{
  "rin": "ABC1234",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "UNCLAIMED",
  "issued_at": "...",
  "claim_token": "secret-token"
}

⚠️ claim_token must never be logged or printed.

⸻

4️⃣ Public Lookup (Issuer Endpoint)

curl https://api.cvsyn.com/api/id/ABC1234

UNCLAIMED response:

{
  "rin": "ABC1234",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "UNCLAIMED"
}

CLAIMED response:

{
  "rin": "ABC1234",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "CLAIMED",
  "claimed_by": "minijun"
}

Public endpoint never exposes api_key, claim_token, or internal timestamps.

⸻

5️⃣ Claim Ownership

curl -X POST https://api.cvsyn.com/api/claim \
  -H "Content-Type: application/json" \
  -d '{"rin":"ABC1234","claimed_by":"minijun","claim_token":"secret-token"}'


⸻

🔄 API Key Lifecycle

Rotate Key

curl -X POST https://api.cvsyn.com/api/v1/agents/rotate-key \
  -H "Authorization: Bearer rin_old"

Lifecycle Guarantee:
- old key becomes immediately invalid (401)
- new key becomes immediately valid (200)
- rotation is atomic

⸻

Revoke Key

curl -X POST https://api.cvsyn.com/api/v1/agents/revoke \
  -H "Authorization: Bearer rin_current"

After revoke:
	•	key → 401

⸻

🧪 End-to-End Verification

This repository includes a full lifecycle verification script:

scripts/rin-e2e-test.sh

Requirements
	•	bash
	•	curl
	•	jq

Run

chmod +x scripts/rin-e2e-test.sh
./scripts/rin-e2e-test.sh

The script validates:
	•	Agent onboarding
	•	Write authentication enforcement
	•	Claim flow correctness
	•	Public issuer field restrictions
	•	Rotate/revoke lifecycle
	•	Key invalidation guarantees

Sensitive keys/tokens are never printed.

⸻

🏛 Design Principles
	•	Minimal surface area
	•	Explicit lifecycle guarantees
	•	Strict public field policy
	•	Stateless verification model
	•	Agent identity separation
	•	No secret leakage in issuer responses

⸻

📜 License

MIT
