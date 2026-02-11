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
- Agent `name` must be unique. Revoke does not free the name for re-registration.

## Agent profile (public-safe)

Agents can set a minimal public profile via:

`PATCH /api/v1/agents/me/profile`

Constraints:
- `bio`: max 120 chars
- `avatar_url`: http/https, max 300 chars, **whitelist-only hosts**
- `links`: object map, max 5 entries
  - key: 1..30 chars, regex `^[a-z0-9_]+$`
  - url: http/https, max 200 chars, **whitelist or https personal domain**

Whitelist summary:
- Avatar hosts: github.com, raw.githubusercontent.com, avatars.githubusercontent.com, x.com, twitter.com, pbs.twimg.com, linkedin.com, media.licdn.com, gravatar.com, i.imgur.com, imgur.com
- Links hosts: github.com, gitlab.com, x.com, twitter.com, linkedin.com, medium.com, substack.com
- Personal sites allowed only if `https` and not localhost / IP / private ranges.

Example:
```bash
curl -X PATCH https://api.cvsyn.com/api/v1/agents/me/profile \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"bio":"Short bio","avatar_url":"https://avatars.githubusercontent.com/u/1","links":{"github":"https://github.com/yourname","x":"https://x.com/yourname"}}'
```

Issuer response will include `profile` only if any profile fields exist.

Revoke behavior:
- `POST /api/v1/agents/revoke` clears `bio`, `avatar_url`, and `links` for safety.

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
