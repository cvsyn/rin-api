#!/usr/bin/env bash
set -euo pipefail

# RIN 1.0.0 — E2E QA script (repo-ready)
#
# HARD RULES:
# 1) Never print api_key / claim_token (not even partially masked).
# 2) All HTTP requests must go to https://api.cvsyn.com only.
# 3) Decide pass/fail primarily by HTTP status codes.
#
# Dependencies: bash, curl, jq

API_BASE="https://api.cvsyn.com"

AGENT_REGISTER="$API_BASE/api/v1/agents/register"
AGENT_ME="$API_BASE/api/v1/agents/me"
AGENT_ROTATE="$API_BASE/api/v1/agents/rotate-key"
AGENT_REVOKE="$API_BASE/api/v1/agents/revoke"

RIN_REGISTER="$API_BASE/api/register"
RIN_CLAIM="$API_BASE/api/claim"
RIN_ID="$API_BASE/api/id"

TMP_BODY_FILE="$(mktemp)"
TMP_STATUS_FILE="$(mktemp)"
trap 'rm -f "$TMP_BODY_FILE" "$TMP_STATUS_FILE"' EXIT

curl_json() {
  local method="$1" url="$2" token="${3-}" data="${4-}"
  local out status body

  if [[ -n "$token" ]]; then
    if [[ -n "$data" ]]; then
      out="$(curl -sS -X "$method" "$url" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$data" -w $'\n%{http_code}')"
    else
      out="$(curl -sS -X "$method" "$url" \
        -H "Authorization: Bearer $token" \
        -w $'\n%{http_code}')"
    fi
  else
    if [[ -n "$data" ]]; then
      out="$(curl -sS -X "$method" "$url" \
        -H "Content-Type: application/json" \
        -d "$data" -w $'\n%{http_code}')"
    else
      out="$(curl -sS -X "$method" "$url" -w $'\n%{http_code}')"
    fi
  fi

  status="${out##*$'\n'}"
  body="${out%$'\n'*}"

  printf '%s' "$body" >"$TMP_BODY_FILE"
  printf '%s' "$status" >"$TMP_STATUS_FILE"
}

# A) Agent onboarding
UNIQ_NAME="rin-e2e-$(date +%s)-$$"

curl_json POST "$AGENT_REGISTER" "" "$(jq -nc --arg name "$UNIQ_NAME" '{name:$name, description:"e2e"}')"
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
if [[ "$STATUS" != "201" && "$STATUS" != "200" ]]; then
  echo "register_agent: FAIL(status=$STATUS)" >&2
  exit 1
fi

# NOTE: register response key path is .agent.api_key (NOT .api_key)
API_KEY="$(printf '%s' "$BODY" | jq -r '.agent.api_key // empty')"
if [[ -z "$API_KEY" ]]; then
  echo "register_agent: FAIL(no api_key)" >&2
  exit 1
fi
echo "register_agent: OK"

ME_OLD_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $API_KEY" "$AGENT_ME")"
echo "me(old): $ME_OLD_STATUS"
[[ "$ME_OLD_STATUS" == "200" ]] || { echo "me(old) unexpected status" >&2; exit 1; }

# B) Write protection
curl_json POST "$RIN_REGISTER" "" "$(jq -nc '{agent_type:"test", agent_name:"no-auth"}')"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "register_unauth: $STATUS"
if [[ "$STATUS" != "401" && "$STATUS" != "403" ]]; then
  echo "register_unauth unexpected status" >&2
  exit 1
fi

curl_json POST "$RIN_REGISTER" "$API_KEY" "$(jq -nc --arg name "$UNIQ_NAME" '{agent_type:"test", agent_name:$name}')"
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "register_auth: $STATUS"
if [[ "$STATUS" != "201" && "$STATUS" != "200" ]]; then
  echo "register_auth unexpected status" >&2
  exit 1
fi

RIN="$(printf '%s' "$BODY" | jq -r '.rin // empty')"
CLAIM_TOKEN="$(printf '%s' "$BODY" | jq -r '.claim_token // empty')"
if [[ -z "$RIN" || -z "$CLAIM_TOKEN" ]]; then
  echo "register_auth: FAIL(rin/claim_token missing)" >&2
  exit 1
fi

# C) Claim flow + issuer spec checks
curl_json GET "$RIN_ID/$RIN" ""
BODY="$(cat "$TMP_BODY_FILE")"
STATUS_FIELD="$(printf '%s' "$BODY" | jq -r '.status // empty')"

FIELDS_OK_BEFORE=true
if ! printf '%s' "$BODY" | jq -e '.rin and .agent_type and .agent_name and .status' >/dev/null 2>&1; then
  FIELDS_OK_BEFORE=false
fi
if printf '%s' "$BODY" | jq -e 'has("api_key") or has("claim_token") or has("issued_at") or has("claimed_by")' >/dev/null 2>&1; then
  FIELDS_OK_BEFORE=false
fi

echo -n "id_before_claim: $STATUS_FIELD"
if [[ "$STATUS_FIELD" != "UNCLAIMED" ]]; then
  echo " + fields_bad"
  echo "issuer status_before must be UNCLAIMED" >&2
  exit 1
fi
if [[ "$FIELDS_OK_BEFORE" == true ]]; then
  echo " + fields_ok"
else
  echo " + fields_bad"
  echo "issuer fields before claim invalid" >&2
  exit 1
fi

BAD_TOKEN="${CLAIM_TOKEN}x"
CLAIMER="rin-test-claimer"

curl_json POST "$RIN_CLAIM" "" "$(jq -nc --arg rin "$RIN" --arg by "$CLAIMER" --arg token "$BAD_TOKEN" '{rin:$rin, claimed_by:$by, claim_token:$token}')"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "claim_wrong: $STATUS"
if [[ "$STATUS" != "403" && "$STATUS" != "400" && "$STATUS" != "401" ]]; then
  echo "claim_wrong unexpected status" >&2
  exit 1
fi

curl_json POST "$RIN_CLAIM" "" "$(jq -nc --arg rin "$RIN" --arg by "$CLAIMER" --arg token "$CLAIM_TOKEN" '{rin:$rin, claimed_by:$by, claim_token:$token}')"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "claim_ok: $STATUS"
[[ "$STATUS" == "200" ]] || { echo "claim_ok unexpected status" >&2; exit 1; }

curl_json GET "$RIN_ID/$RIN" ""
BODY="$(cat "$TMP_BODY_FILE")"
STATUS_FIELD="$(printf '%s' "$BODY" | jq -r '.status // empty')"

CLAIMED_BY_PRESENT=false
FIELDS_OK_AFTER=true

if printf '%s' "$BODY" | jq -e 'has("claimed_by") and (.claimed_by != null) and (.claimed_by|tostring|length > 0)' >/dev/null 2>&1; then
  CLAIMED_BY_PRESENT=true
fi
if ! printf '%s' "$BODY" | jq -e '.rin and .agent_type and .agent_name and .status' >/dev/null 2>&1; then
  FIELDS_OK_AFTER=false
fi
if printf '%s' "$BODY" | jq -e 'has("api_key") or has("claim_token") or has("issued_at")' >/dev/null 2>&1; then
  FIELDS_OK_AFTER=false
fi

echo -n "id_after_claim: $STATUS_FIELD"
if [[ "$STATUS_FIELD" != "CLAIMED" ]]; then
  echo " + claimed_by_missing + fields_bad"
  echo "issuer status_after must be CLAIMED" >&2
  exit 1
fi

if [[ "$CLAIMED_BY_PRESENT" == true ]]; then
  echo -n " + claimed_by_present"
else
  echo -n " + claimed_by_missing"
  FIELDS_OK_AFTER=false
fi

if [[ "$FIELDS_OK_AFTER" == true ]]; then
  echo " + fields_ok"
else
  echo " + fields_bad"
  echo "issuer fields after claim invalid" >&2
  exit 1
fi

# D) Key lifecycle (rotate / revoke)
curl_json POST "$AGENT_ROTATE" "$API_KEY" "{}"
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
if [[ "$STATUS" != "200" ]]; then
  echo "rotate: FAIL(status=$STATUS)" >&2
  exit 1
fi

NEW_KEY="$(printf '%s' "$BODY" | jq -r '.api_key // empty')"
ROTATED="$(printf '%s' "$BODY" | jq -r '.rotated // empty')"
if [[ -z "$NEW_KEY" || "$ROTATED" != "true" ]]; then
  echo "rotate: FAIL(new_key/rotated)" >&2
  exit 1
fi
echo "rotate: OK (newkey captured)"

ME_OLD_AFTER_ROTATE="$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $API_KEY" "$AGENT_ME")"
ME_NEW_AFTER_ROTATE="$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $NEW_KEY" "$AGENT_ME")"
echo "me(old_after_rotate): $ME_OLD_AFTER_ROTATE"
echo "me(new_after_rotate): $ME_NEW_AFTER_ROTATE"

if [[ "$ME_OLD_AFTER_ROTATE" != "401" && "$ME_OLD_AFTER_ROTATE" != "403" ]]; then
  echo "old key should be invalid after rotate" >&2
  exit 1
fi
[[ "$ME_NEW_AFTER_ROTATE" == "200" ]] || { echo "new key should be valid after rotate" >&2; exit 1; }

curl_json POST "$AGENT_REVOKE" "$NEW_KEY" "{}"
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"

REVOKED_FLAG="$(printf '%s' "$BODY" | jq -r '.revoked // empty')"
echo "revoke: revoked:$REVOKED_FLAG"
if [[ "$STATUS" != "200" || "$REVOKED_FLAG" != "true" ]]; then
  echo "revoke failed" >&2
  exit 1
fi

ME_NEW_AFTER_REVOKE="$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $NEW_KEY" "$AGENT_ME")"
echo "me(new_after_revoke): $ME_NEW_AFTER_REVOKE"
if [[ "$ME_NEW_AFTER_REVOKE" != "401" && "$ME_NEW_AFTER_REVOKE" != "403" ]]; then
  echo "new key should be invalid after revoke" >&2
  exit 1
fi

# E) Re-register revoked name (revive)
curl_json POST "$AGENT_REGISTER" "" "$(jq -nc --arg name "$UNIQ_NAME" '{name:$name, description:"re-registered"}')"
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
if [[ "$STATUS" != "201" && "$STATUS" != "200" ]]; then
  echo "reregister: FAIL(status=$STATUS)" >&2
  exit 1
fi

REVIVED_KEY="$(printf '%s' "$BODY" | jq -r '.agent.api_key // empty')"
if [[ -z "$REVIVED_KEY" ]]; then
  echo "reregister: FAIL(no api_key)" >&2
  exit 1
fi

ME_REVIVED_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $REVIVED_KEY" "$AGENT_ME")"
echo "me(revived): $ME_REVIVED_STATUS"
[[ "$ME_REVIVED_STATUS" == "200" ]] || { echo "revived key should be 200" >&2; exit 1; }

echo "DONE ✅"
