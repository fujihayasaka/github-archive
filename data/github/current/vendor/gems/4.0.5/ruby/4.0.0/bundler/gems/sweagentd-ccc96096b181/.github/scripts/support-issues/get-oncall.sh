#!/bin/bash
# Script to fetch the current on-call engineer from PagerDuty
# Returns the on-call handle or falls back to team mention

PAGERDUTY_API_KEY="${1:-$PAGERDUTY_API_KEY}"
ESCALATION_ID="${2:-P29A2BN}"
FALLBACK_ONCALL="github/copilot-extensibility-team"

if [ -z "$PAGERDUTY_API_KEY" ]; then
  echo "Error: PAGERDUTY_API_KEY is required" >&2
  echo "$FALLBACK_ONCALL"
  exit 0
fi

# Fetch the current on-call user from PagerDuty escalation
# Use a temporary file to capture curl exit code
TEMP_RESPONSE=$(mktemp)
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_RESPONSE" -X GET \
  "https://api.pagerduty.com/oncalls?escalation_policy_ids[]=${ESCALATION_ID}" \
  -H "Authorization: Token token=${PAGERDUTY_API_KEY}" \
  -H "Accept: application/vnd.pagerduty+json;version=2" 2>/dev/null)
CURL_EXIT=$?
RESPONSE=$(cat "$TEMP_RESPONSE")
rm -f "$TEMP_RESPONSE"

# Check if curl command succeeded
if [ $CURL_EXIT -ne 0 ]; then
  echo "PagerDuty API call failed (curl exit code: $CURL_EXIT)" >&2
  echo "$FALLBACK_ONCALL"
  exit 0
fi

# Separate the response body and the HTTP status code
HTTP_STATUS="$HTTP_CODE"

# Check if HTTP_STATUS is a valid number
if ! [[ "$HTTP_STATUS" =~ ^[0-9]+$ ]]; then
  echo "PagerDuty API call failed (invalid status code: $HTTP_STATUS)" >&2
  echo "$FALLBACK_ONCALL"
  exit 0
fi

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
  echo "PagerDuty API call failed with HTTP status $HTTP_STATUS" >&2
  echo "$FALLBACK_ONCALL"
  exit 0
elif [ -z "$RESPONSE" ] || ! echo "$RESPONSE" | jq . >/dev/null 2>&1; then
  echo "PagerDuty API call returned invalid or empty JSON" >&2
  echo "$FALLBACK_ONCALL"
  exit 0
fi

ONCALL_HANDLE=$(echo "$RESPONSE" | jq -r '.oncalls[] | select(.escalation_level == 1) | .user | .summary' | head -n1)

if [ -z "$ONCALL_HANDLE" ] || [ "$ONCALL_HANDLE" = "null" ]; then
  echo "Could not determine on-call handle from PagerDuty response" >&2
  echo "$FALLBACK_ONCALL"
  exit 0
fi

echo "$ONCALL_HANDLE"
