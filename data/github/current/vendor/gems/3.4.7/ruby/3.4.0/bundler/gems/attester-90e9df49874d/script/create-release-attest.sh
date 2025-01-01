#!/bin/bash

# filepath: /Users/eugenejahn/workspace/attester/script/create-release-attest.sh

# Define variables
REQUEST_URL="https://attester-staging.service.iad.github.net/twirp/attester.v0.ReleaseAPI/CreateReleaseAttestation"
REQUEST_FILE="example/release_statement_03_06_2025.json"
HMAC_KEY="dotcomsecretkey"
OUTPUT_FILE="bundle"

# Run the Go script and store the response in a temporary file
TEMP_FILE=$(mktemp)
go run script/body-hmac-request.go \
  -request-body "{\"statement\":$(cat $REQUEST_FILE)}" \
  -request-url $REQUEST_URL \
  -hmac-key $HMAC_KEY > $TEMP_FILE

# Check if the command was successful
if [ $? -eq 0 ]; then
  # Extract the value of the bundle field and store it in the output file
  jq -r '.bundle' $TEMP_FILE > $OUTPUT_FILE
  echo "Bundle value stored in $OUTPUT_FILE"
else
  echo "Failed to store response"
  exit 1
fi

# Clean up the temporary file
rm $TEMP_FILE
