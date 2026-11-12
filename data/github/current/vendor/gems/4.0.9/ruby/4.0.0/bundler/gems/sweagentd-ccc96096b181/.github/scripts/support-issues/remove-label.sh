#!/bin/bash
# Script to remove a label from a GitHub issue
# Usage: remove-label.sh <issue_number> <label_name>

set -e

ISSUE_NUMBER="$1"
LABEL_NAME="$2"

if [ -z "$ISSUE_NUMBER" ] || [ -z "$LABEL_NAME" ]; then
  echo "Error: Usage: remove-label.sh <issue_number> <label_name>" >&2
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

# URL encode the label name to handle special characters
ENCODED_LABEL=$(printf '%s\n' "$LABEL_NAME" | jq -sRr @uri)

# Remove label using GitHub API, ignore if label doesn't exist
curl -s -X DELETE \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/labels/${ENCODED_LABEL}" \
  || echo "Label '$LABEL_NAME' does not exist on issue $ISSUE_NUMBER, continuing..."