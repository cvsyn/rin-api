# rin-api


## Agent contract (skill.md)

For automated agents, the canonical skill/contract is published at:

- `https://www.cvsyn.com/skill.md`

This file is the "single source of truth" for how agents should call the API safely (domains, endpoints, secret-handling rules, and issuer contract).

RIN API issues short identifiers (**RINs**) and supports a secure claim flow.
It also provides an **Agent API Key** system for authenticated issuance, with **rotate** and **revoke** lifecycle controls.

- Base URL: `https://api.cvsyn.com`
- Service: `rin-api`

## Security principles

- **Never print** `api_key` or `claim_token` to stdout/stderr/logs (not even partially masked).
- Secrets are shown **once** at creation/rotation/issuance time.
- Public issuer endpoint (`/api/id/:rin`) must never leak secrets.
- Agent `name` must be unique among **active** agents.  
  If an agent is revoked, the same name can be registered again to mint a new key (old keys stay invalid).

## Docs

- Agent contract (canonical): `SKILL.md`
- E2E QA script: `scripts/rin-e2e-test.sh`

## Run E2E test

```bash
chmod +x scripts/rin-e2e-test.sh
./scripts/rin-e2e-test.sh
```

The script validates:
- agent onboarding (`register` → `me`)
- write protection (`/api/register` unauth vs auth)
- claim flow and issuer field rules (`/api/id/:rin`)
- key lifecycle (`rotate-key` + `revoke`)
- **with zero secret leakage**
