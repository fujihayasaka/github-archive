#!/bin/bash

set -eo pipefail

#!/bin/bash

# Copied from https://github.com/github/ABS/blob/1e37ef636f4e28826dc4f016c493d79d42964d69/paved-path/codespaces-terraform/scripts/credentials_terraform.sh
echo "Setting up Terraform credentials"

if ! [ -x "$(command -v jq)" ]; then
  echo 'Error: jq is not installed. jq is required to proceed.' >&2
  exit 1
fi

if [ -z "$GH_CS_TERRAFORM_LOGIN_TOKEN" ]; then
  echo 'Error: GH_CS_TERRAFORM_LOGIN_TOKEN env var is not set. GH_CS_TERRAFORM_LOGIN_TOKEN is required to proceed.' >&2
  echo 'See https://github.com/github/ABS/blob/1e37ef636f4e28826dc4f016c493d79d42964d69/docs/getting-started.md#scripts-for-codespace-setup for setting this up.' >&2
  exit 1
fi

mkdir -p "$HOME"/.terraform.d
jq -n --arg token "$GH_CS_TERRAFORM_LOGIN_TOKEN" \
  '{credentials: { "terraform.githubapp.com": { token: $token } } }' > "$HOME"/.terraform.d/credentials.tfrc.json

echo "Finished setting up Terraform credentials"
