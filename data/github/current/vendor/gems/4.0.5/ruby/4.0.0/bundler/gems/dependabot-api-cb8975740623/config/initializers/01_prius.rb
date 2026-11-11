# frozen_string_literal: true

Prius.load(:enterprise, required: false, type: :bool)
Prius.load(:proxima_stamp, required: false)

Prius.load(:target_github_url)
Prius.load(:target_github_internal_url, required: Dependabot.enterprise? && Rails.env.production?)
Prius.load(:github_internal_twirp_hmac_key)
Prius.load(:api_internal_actions_dynamic_workflows_hmac_client_key, required: false)
Prius.load(:github_integration_id, type: :int)
Prius.load(:github_integration_node_id)
Prius.load(:github_integration_name)
Prius.load(:github_integration_webhook_secret)
Prius.load(:github_integration_private_key)
Prius.load(:github_dependabot_user_id, type: :int)
Prius.load(:dependabot_api_hmac_keys)
Prius.load(:dependabot_service_token)
Prius.load(:kube_region)
Prius.load(:dependabot_api_endpoint)
Prius.load(:aqueduct_url)
Prius.load(:aqueduct_api_key, required: Rails.env.production? && Dependabot.dotcom?)
Prius.load(:aqueduct_api_key_version, required: Rails.env.production? && Dependabot.dotcom?)

# NextGlobalID format for the github_integration
Prius.load(:github_integration_next_global_id, required: !Prius.get(:enterprise))

Prius.load(:redis_encryption_key)
Prius.load(:redis_password, required: Rails.env.production? && !Dependabot.enterprise?)
Prius.load(:redis_url)
Prius.load(:temporary_file_encryption_key)

Prius.load(:aws_access_key_id)
Prius.load(:aws_secret_access_key)
Prius.load(:aws_region)
Prius.load(:dependency_files_s3_bucket)
Prius.load(:update_job_log_bucket)

# Azure storage accounts for Proxima and dotcom
Prius.load(:azure_storage_account, required: Rails.env.production? && !Dependabot.enterprise?)
Prius.load(:azure_storage_access_key, required: Rails.env.production? && !Dependabot.enterprise?)
Prius.load(:azure_storage_container, required: Rails.env.production? && !Dependabot.enterprise?)

# Secrets access
Prius.load(:earthsmoke_dependabot_secrets_key, required: !Prius.get(:enterprise))
Prius.load(:kredz_addr)
Prius.load(:kredz_hmac_key)

# Interactions with Dependency Graph
Prius.load(:dsapi_internal_url, required: !Dependabot.enterprise?)
Prius.load(:dsapi_hmac_key, required: !Dependabot.enterprise?)

################
# Not required #
################

# For pointing to an internally-hosted S3 bucket
Prius.load(:aws_endpoint, required: false)

# Is this the badge service?
Prius.load(:badge_service, required: false)

# Is this the actions deployment?
Prius.load(:actions_deployment, required: false, type: :bool)

# Optional configuration for runners accessing Dependabot API within
# containers if different to `dependabot_api_endpoint`
Prius.load(:dependabot_api_container_endpoint, required: false)

Prius.load(:dotcom_dependabot_api_internal_url, required: Dependabot.proxima? && Rails.env.production?)

# Testing/Dev flag to enable onboarding accounts without app installations
Prius.load(:global_app_onboarding, required: false, type: :bool)

# Configuration for Proxima Service Identity
Prius.load(:proxima_service_identity_secret_key, required: Dependabot.proxima? && Rails.env.production?)

# PAT that we're using to fetch the `@github/dependabot-autofix` package in the
# autofix dynamic workflow
Prius.load(:dependabot_autofix_npm_token, required: false)
Prius.load(:dependabot_security_events_token, required: false)
