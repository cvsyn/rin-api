# RIN API

## Anyone can look up the ID (PUBLIC)
Endpoint: `GET /api/id/:rin`

Response (minimal):
```json
{
  "rin": "KU2HLH",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "UNCLAIMED"
}
```

If status is CLAIMED, `claimed_by` is included:
```json
{
  "rin": "KU2HLH",
  "agent_type": "openclaw",
  "agent_name": "prod",
  "status": "CLAIMED",
  "claimed_by": "Acme Labs"
}
```

Public lookup never returns `claim_token` or any secrets.
