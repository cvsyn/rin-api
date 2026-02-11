# rin-api

RIN API issues short identifiers (**RINs**) and supports a secure claim flow.
It also provides an **Agent API Key** system for authenticated issuance, with **rotate** and **revoke** lifecycle controls.

- Base URL: `https://api.cvsyn.com`
- Service: `rin-api`

## Security principles

- **Never print** `api_key` or `claim_token` to stdout/stderr/logs (not even partially masked).
- Secrets are shown **once** at creation/rotation/issuance time.
- Public issuer endpoint (`/api/id/:rin`) must never leak secrets.

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
