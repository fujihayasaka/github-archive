#!/bin/bash
# Script to close a GitHub issue
# Usage: close-issue.sh <issue_number>

set -e

ISSUE_NUMBER="$1"

if [ -z "$ISSUE_NUMBER" ]; then
  echo "Error: Usage: close-issue.sh <issue_number>" >&2
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

# Create JSON payload
PAYLOAD='{"state": "closed"}'

# Close issue using GitHub API
curl -s -X PATCH \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}" \
  -d "$PAYLOAD"
