#!/bin/bash

# This script is used to create vault resources for a new stamp in Proxima.
# It copies the secrets from an existing stamp (prod-weu-01) and updates the
# secrets that are stamp specific.

# Running the Script:
# 1. Login to prod shell and execute the ". vault-login" command
# 2. Save the script to a file, for example stamp-vault-resource-creation.sh
# 3. Make the script executable: chmod +x stamp-vault-resource-creation.sh
# 4. Run the script with the stamp name and Azure region as arguments: ./stamp-vault-resource-creation.sh prod-sdc-01 swedencentral

# Function to print usage
print_usage() {
  echo "Usage: $0 <STAMP_NAME> <STAMP_AZURE_REGION>"
  exit 1
}

# Check if STAMP_NAME and STAMP_AZURE_REGION are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: STAMP_NAME and STAMP_AZURE_REGION are required."
  print_usage
fi

# Set STAMP_NAME and STAMP_AZURE_REGION
STAMP_NAME=$1
STAMP_AZURE_REGION=$2
export STAMP_NAME
export STAMP_AZURE_REGION

# Existing vault secret Stamp
EXISTING_VAULT_SECRET_PROXIMA_STAMP=prod-weu-01

# Function to execute vault-secret command and check for errors
execute_vault_command() {
  local command=$1
  echo "Executing: $command"
  eval $command
  if [ $? -ne 0 ]; then
    echo "Error: Failed to execute $command"
    exit 1
  fi
}

# List of secrets that do not need updating
NO_UPDATE_SECRETS=(
  "BUILD_GITHUB_DCE_CORE_SERVICES_SECRET_CHATTERBOX_TOKEN"
  "CREDENTIALS_ENCRYPTION_KEY"
  "CHATOPS_AUTH_PUBLIC_KEY"
  "CHATTERBOX_TOKEN"
  "EARTHSMOKE_TOKEN"
  "PAGERDUTY_ICS_URL"
  "RPC_PUBLIC_KEY"
  "SPOKESD_CHATTERBOX_TOKEN"
  "VAULT_TOKEN"
  "spn_dependabot_api_tf"
  "spn_dependabot_api_tf_client_id"
  "spn_dependabot_api_tf_tenant_id"
)

# Step 2: Create environment in Vault
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --catalog-service dependabot-api --init"


# Step 3: Set various secrets
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key GITHUB_INTERNAL_TWIRP_HMAC_KEY -l <(head --bytes=32 /dev/urandom | xxd -p -c 0 | tr -d '\n')"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key GITHUB_INTEGRATION_WEBHOOK_SECRET -l <(openssl rand -hex 32 | tr -d '\n')"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key TEMPORARY_FILE_ENCRYPTION_KEY -l <(openssl rand -base64 32 | tr -d '\n')"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key REDIS_ENCRYPTION_KEY -l <(openssl rand -base64 32 | tr -d '\n')"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key DEPENDABOT_API_HMAC_KEYS -l <(openssl rand -hex 32 | tr -d '\n')"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key DEPENDABOT_SERVICE_TOKEN -l <(openssl rand -hex 32 | tr -d '\n')"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key SECRET_KEY_BASE -l <(openssl rand -hex 64 | tr -d '\n')"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key GITHUB_INTEGRATION_PRIVATE_KEY -l ${STAMP_NAME}.key --newline-override"
execute_vault_command "vault-secret --application dependabot-api --environment ${STAMP_NAME} --key DEPENDABOT_INTERNAL_URL -v http://dependabot-internal.dependabot-api-${STAMP_NAME}.svc.cluster.local"

echo "All vault-secret commands executed successfully."


echo ""
echo "The following secrets do not need to be updated as they are stamps agnostic as of now"
for secret in "${NO_UPDATE_SECRETS[@]}"; do
  echo "- ${secret}"
done

echo ""
echo "Execute the below command and secrets marked with TODO need to be updated manually"
echo "vault-secret -a dependabot-api -e ${STAMP_NAME}"
