#!/bin/bash
# Script to post a comment to a GitHub issue
# Usage: post-comment.sh <issue_number> <comment_body>

set -e

ISSUE_NUMBER="$1"
COMMENT_BODY="$2"

if [ -z "$ISSUE_NUMBER" ] || [ -z "$COMMENT_BODY" ]; then
  echo "Error: Usage: post-comment.sh <issue_number> <comment_body>" >&2
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
PAYLOAD=$(jq -n --arg body "$COMMENT_BODY" '{body: $body}')

# Post comment using GitHub API
curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/comments" \
  -d "$PAYLOAD"
