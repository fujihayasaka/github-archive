# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitHubForMac
      GITHUB_MAC_CLIENT_ID = "eac522c6b68c504b2aac".freeze

      PRODUCTION = {
        alias: :github_for_mac,
        database_lookup_attributes: { key: GITHUB_MAC_CLIENT_ID },
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
    end
  end
end
