#!/bin/bash
# Script to handle reopened issues - check labels and notify accordingly
# Usage: handle-reopened.sh <issue_number>

set -e

ISSUE_NUMBER="$1"

if [ -z "$ISSUE_NUMBER" ]; then
  echo "Error: Usage: handle-reopened.sh <issue_number>" >&2
  exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN environment variable is required" >&2
  exit 1
fi

if [ -z "$GITHUB_REPOSITORY" ]; then
  echo "Error: GITHUB_REPOSITORY environment variable is required" >&2
  exit 1
fi

# Get issue details including labels
ISSUE_DATA=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}")

# Extract labels
LABELS=$(echo "$ISSUE_DATA" | jq -r '.labels[].name')

# Check if needs-product-triage label is present
if echo "$LABELS" | grep -q "support-issue:needs-product-triage"; then
  COMMENT_BODY=$(./.github/scripts/support-issues/get-comment.sh product-triage-reopened)
  ./.github/scripts/support-issues/post-comment.sh "$ISSUE_NUMBER" "$COMMENT_BODY"
# Check if needs-engineering-triage label is present
elif echo "$LABELS" | grep -q "support-issue:needs-engineering-triage"; then
  # Get on-call engineer from PagerDuty
  ONCALL_HANDLE=$(./.github/scripts/support-issues/get-oncall.sh "$PAGERDUTY_API_KEY" "P29A2BN")
  COMMENT_BODY=$(./.github/scripts/support-issues/get-comment.sh engineering-triage-reopened "$ONCALL_HANDLE")
  ./.github/scripts/support-issues/post-comment.sh "$ISSUE_NUMBER" "$COMMENT_BODY"
fi
