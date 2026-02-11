#!/usr/bin/env bash
set -euo pipefail

# RIN E2E test (public API)
# - Requires: bash, curl, jq
# - Never prints: agent api_key, claim_token, rotated api_key
# - Validates: A/B/C/D flows + issuer field constraints + key lifecycle
#
# Usage:
#   chmod +x scripts/rin-e2e-test.sh
#   ./scripts/rin-e2e-test.sh
#
# Optional:
#   API_BASE=https://api.cvsyn.com ./scripts/rin-e2e-test.sh

API_BASE="${API_BASE:-https://api.cvsyn.com}"

AGENT_REGISTER="$API_BASE/api/v1/agents/register"
AGENT_ME="$API_BASE/api/v1/agents/me"
AGENT_ROTATE="$API_BASE/api/v1/agents/rotate-key"
AGENT_REVOKE="$API_BASE/api/v1/agents/revoke"

RIN_REGISTER="$API_BASE/api/register"
RIN_CLAIM="$API_BASE/api/claim"
RIN_ID="$API_BASE/api/id"

TMP_BODY_FILE="$(mktemp)"
TMP_STATUS_FILE="$(mktemp)"
cleanup() { rm -f "$TMP_BODY_FILE" "$TMP_STATUS_FILE"; }
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Helper: capture JSON body + HTTP status (without printing raw body)
# -----------------------------------------------------------------------------
curl_json() {
  local method="$1" url="$2" token="${3-}" data="${4-}"
  local combined status body

  if [[ -n "$token" && -n "$data" ]]; then
    combined="$(curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$data" -w $'\n%{http_code}')"
  elif [[ -n "$token" ]]; then
    combined="$(curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $token" \
      -w $'\n%{http_code}')"
  elif [[ -n "$data" ]]; then
    combined="$(curl -sS -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -d "$data" -w $'\n%{http_code}')"
  else
    combined="$(curl -sS -X "$method" "$url" -w $'\n%{http_code}')"
  fi

  status="${combined##*$'\n'}"
  body="${combined%$'\n'*}"

  printf '%s' "$body" >"$TMP_BODY_FILE"
  printf '%s' "$status" >"$TMP_STATUS_FILE"
}

must_status() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" != "$want" ]]; then
    echo "$label: FAIL(status=$got, expected=$want)" >&2
    exit 1
  fi
}

# =============================================================================
# A) Agent onboarding
# =============================================================================
UNIQ_NAME="rin-test-$(date +%s)-$$"

curl_json POST "$AGENT_REGISTER" "" "$(jq -nc --arg name "$UNIQ_NAME" '{name:$name, description:"e2e"}')"
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"

if [[ "$STATUS" != "201" && "$STATUS" != "200" ]]; then
  echo "register_agent: FAIL(status=$STATUS)" >&2
  exit 1
fi

API_KEY="$(echo "$BODY" | jq -r '.agent.api_key // empty')"
if [[ -z "$API_KEY" ]]; then
  echo "register_agent: FAIL(no api_key in response)" >&2
  exit 1
fi

echo "register_agent: OK"

ME_OLD_STATUS="$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $API_KEY" \
  "$AGENT_ME")"
echo "me(old): $ME_OLD_STATUS"
must_status "$ME_OLD_STATUS" "200" "me(old)"

# =============================================================================
# B) Write protection
# =============================================================================
curl_json POST "$RIN_REGISTER" "" "$(jq -nc '{agent_type:"test", agent_name:"rin-ab-test"}')"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "register_unauth: $STATUS"
if [[ "$STATUS" != "401" && "$STATUS" != "403" ]]; then
  echo "register_unauth: FAIL(status=$STATUS, expected 401/403)" >&2
  exit 1
fi

curl_json POST "$RIN_REGISTER" "$API_KEY" \
  "$(jq -nc --arg name "$UNIQ_NAME" '{agent_type:"test", agent_name:$name}')"
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "register_auth: $STATUS"
if [[ "$STATUS" != "201" && "$STATUS" != "200" ]]; then
  echo "register_auth: FAIL(status=$STATUS)" >&2
  exit 1
fi

RIN="$(echo "$BODY" | jq -r '.rin // empty')"
CLAIM_TOKEN="$(echo "$BODY" | jq -r '.claim_token // empty')"
if [[ -z "$RIN" || -z "$CLAIM_TOKEN" ]]; then
  echo "register_auth: FAIL(rin/claim_token missing)" >&2
  exit 1
fi

# =============================================================================
# C) Claim flow + issuer field constraints
# =============================================================================
curl_json GET "$RIN_ID/$RIN" ""
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
STATUS_FIELD="$(echo "$BODY" | jq -r '.status // empty')"

FIELDS_OK_BEFORE=true
if ! echo "$BODY" | jq -e '.rin and .agent_type and .agent_name and .status' >/dev/null 2>&1; then
  FIELDS_OK_BEFORE=false
fi
if echo "$BODY" | jq -e 'has("api_key") or has("claim_token") or has("issued_at") or has("claimed_by")' >/dev/null 2>&1; then
  FIELDS_OK_BEFORE=false
fi

echo -n "id_before_claim: $STATUS_FIELD"
if [[ "$FIELDS_OK_BEFORE" == true ]]; then
  echo " + fields_ok"
else
  echo " + fields_bad" >&2
  exit 1
fi

BAD_TOKEN="${CLAIM_TOKEN}x"
CLAIMER="rin-test-claimer"

curl_json POST "$RIN_CLAIM" "" \
  "$(jq -nc --arg rin "$RIN" --arg token "$BAD_TOKEN" --arg by "$CLAIMER" \
    '{rin:$rin, claimed_by:$by, claim_token:$token}')"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "claim_wrong: $STATUS"
if [[ "$STATUS" != "403" && "$STATUS" != "401" && "$STATUS" != "400" ]]; then
  echo "claim_wrong: FAIL(status=$STATUS, expected 400/401/403)" >&2
  exit 1
fi

curl_json POST "$RIN_CLAIM" "" \
  "$(jq -nc --arg rin "$RIN" --arg token "$CLAIM_TOKEN" --arg by "$CLAIMER" \
    '{rin:$rin, claimed_by:$by, claim_token:$token}')"
STATUS="$(cat "$TMP_STATUS_FILE")"
echo "claim_ok: $STATUS"
must_status "$STATUS" "200" "claim_ok"

curl_json GET "$RIN_ID/$RIN" ""
BODY="$(cat "$TMP_BODY_FILE")"
STATUS_FIELD="$(echo "$BODY" | jq -r '.status // empty')"

CLAIMED_BY_PRESENT=false
FIELDS_OK_AFTER=true

if echo "$BODY" | jq -e 'has("claimed_by") and (.claimed_by|type=="string") and (.claimed_by|length>0)' >/dev/null 2>&1; then
  CLAIMED_BY_PRESENT=true
fi
if ! echo "$BODY" | jq -e '.rin and .agent_type and .agent_name and .status' >/dev/null 2>&1; then
  FIELDS_OK_AFTER=false
fi
if echo "$BODY" | jq -e 'has("api_key") or has("claim_token") or has("issued_at")' >/dev/null 2>&1; then
  FIELDS_OK_AFTER=false
fi

echo -n "id_after_claim: $STATUS_FIELD"
if [[ "$CLAIMED_BY_PRESENT" == true ]]; then
  echo -n " + claimed_by_present"
else
  echo -n " + claimed_by_missing"
  FIELDS_OK_AFTER=false
fi
if [[ "$FIELDS_OK_AFTER" == true ]]; then
  echo " + fields_ok"
else
  echo " + fields_bad" >&2
  exit 1
fi

# =============================================================================
# D) Key lifecycle (rotate / revoke)
# =============================================================================
curl_json POST "$AGENT_ROTATE" "$API_KEY" '{}'
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
must_status "$STATUS" "200" "rotate"

NEW_KEY="$(echo "$BODY" | jq -r '.api_key // empty')"
ROTATED="$(echo "$BODY" | jq -r '.rotated // empty')"
if [[ -z "$NEW_KEY" || "$ROTATED" != "true" ]]; then
  echo "rotate: FAIL(missing new api_key or rotated!=true)" >&2
  exit 1
fi
echo "rotate: OK (newkey captured)"

ME_OLD_AFTER_ROTATE="$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $API_KEY" \
  "$AGENT_ME")"
ME_NEW_AFTER_ROTATE="$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $NEW_KEY" \
  "$AGENT_ME")"

echo "me(old_after_rotate): $ME_OLD_AFTER_ROTATE"
echo "me(new_after_rotate): $ME_NEW_AFTER_ROTATE"

if [[ "$ME_OLD_AFTER_ROTATE" != "401" && "$ME_OLD_AFTER_ROTATE" != "403" ]]; then
  echo "me(old_after_rotate): FAIL(expected 401/403)" >&2
  exit 1
fi
must_status "$ME_NEW_AFTER_ROTATE" "200" "me(new_after_rotate)"

curl_json POST "$AGENT_REVOKE" "$NEW_KEY" '{}'
BODY="$(cat "$TMP_BODY_FILE")"
STATUS="$(cat "$TMP_STATUS_FILE")"
must_status "$STATUS" "200" "revoke"
REVOKED_FLAG="$(echo "$BODY" | jq -r '.revoked // empty')"
echo "revoke: revoked:$REVOKED_FLAG"
if [[ "$REVOKED_FLAG" != "true" ]]; then
  echo "revoke: FAIL(expected revoked=true)" >&2
  exit 1
fi

ME_NEW_AFTER_REVOKE="$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $NEW_KEY" \
  "$AGENT_ME")"
echo "me(new_after_revoke): $ME_NEW_AFTER_REVOKE"
if [[ "$ME_NEW_AFTER_REVOKE" != "401" && "$ME_NEW_AFTER_REVOKE" != "403" ]]; then
  echo "me(new_after_revoke): FAIL(expected 401/403)" >&2
  exit 1
fi

echo "DONE ✅"
