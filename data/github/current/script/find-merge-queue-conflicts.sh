#!/bin/bash

help() {
  echo "Finds PRs in the merge queue ahead which touch the same files, as a potential source of conflict."
  echo
  echo "Usage: script/find-merge-queue-conflicts.sh <source-pr>"
  echo
}

OWNER=github
REPO=github
SOURCE_PR=$1
if [ -z "${SOURCE_PR}" ]; then
  help
  exit 1
fi

echo "Scanning the merge queue for PRs which modify the same files..."
echo

# Get the list of files changed in the original PR
gh pr view https://github.com/${OWNER}/${REPO}/pull/${SOURCE_PR} --json files | jq -r '.files[].path' > /tmp/source.txt

# Get the PRs in the merge queue
gh api graphql -F owner=${OWNER} -F repo=${REPO} -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      mergeQueue {
        entries(first: 100) {
          nodes {
            pullRequest {
              number
            }
          }
        }
      }
    }
  }
' | jq '.data.repository.mergeQueue.entries.nodes[].pullRequest.number' > /tmp/prs.txt

while read TARGET_PR; do
  # If we find our own PR, we're done
  if [ "${TARGET_PR}" == "${SOURCE_PR}" ]; then
    break
  fi

  # Fetch the files changed in the PR
  gh pr view "https://github.com/${OWNER}/${REPO}/pull/${TARGET_PR}" --json files | jq -r '.files[].path' > /tmp/pr-${TARGET_PR}.txt

  # Compare the files changed in the PR to the files changed in the original PR
  files=$(comm -12 "/tmp/source.txt" "/tmp/pr-${TARGET_PR}.txt")
  if [[ "${files}" ]]; then
    echo "Potential conflict with https://github.com/${OWNER}/${REPO}/pull/${TARGET_PR}"
    echo "${files}" | sed 's/^/  - /'
    echo
  fi

  rm /tmp/pr-${TARGET_PR}.txt
done </tmp/prs.txt

rm /tmp/source.txt
rm /tmp/prs.txt
