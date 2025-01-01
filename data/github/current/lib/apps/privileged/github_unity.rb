# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitHubUnity
      GITHUB_UNITY_PROD_CLIENT_ID = "107b906ff287f62a12a4".freeze
      GITHUB_UNITY_DEV_CLIENT_ID  = "924a97f36926f535e72c".freeze

      PRODUCTION = {
        alias: :github_unity,
        database_lookup_attributes: { key: GITHUB_UNITY_PROD_CLIENT_ID },
        inherits: [],
        capabilities: {
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          operated_by_github: true, # Preserves behavior that used to be hard-coded in `OauthApplication`
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          verify_account_ownership: true # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      DEV = {
        alias: :github_unity_dev,
        database_lookup_attributes: { key: GITHUB_UNITY_DEV_CLIENT_ID },
        inherits: [],
        capabilities: {
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          operated_by_github: true, # Preserves behavior that used to be hard-coded in `OauthApplication`
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          verify_account_ownership: true # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: [],
      }

      OAUTH_APPS = [PRODUCTION, DEV]
    end
  end
end
