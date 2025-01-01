#!/bin/bash
#
#/ Usage: reindex.sh target_corpus file.txt
#/
#/ Given a file with one repo ID per line, sends a reindex RPC for each one.
#/ Requires HMAC_KEY to be set in the environment.

set -euo pipefail
IFS=$'\n\t'

function usage {
    grep "^#/" "${BASH_SOURCE[0]}" | cut -c 4-
}

if [ "$#" -ne 2 ]; then
    usage
    exit 1;
fi

target_corpus=$1
file=$2

if [ -z "$HMAC_KEY" ]; then
    echo "error: HMAC_KEY unset, aborting"
    exit 1
fi

if [ ! -f "$file" ]; then
    echo "File $file does not exist"
    exit 1
fi

while read -r repo_id; do
    ts=$(date +%s)
    hmac=$ts.$(echo -n $ts | openssl sha256 -hmac ${HMAC_KEY} | sed 's/^.* //')

    data="{\"force_reindex\": true, \"repo_id\": $repo_id, \"corpus\": "$target_corpus"}"

    curl --request "POST" \
        --header "Content-Type: application/json" \
        --header "Request-HMAC: $hmac" \
        --data "$data" \
        https://blackbird.githubapp.com/twirp/blackbirdmw.admin.v1.AdminAPI/IndexRepo
done < "$file"
