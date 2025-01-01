# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    # This is HyperList for Mac; pending rename of this internal app
    class GitHubPrism
      OAUTH_APP_NAME = "Prism"
      GITHUB_PRISM_CLIENT_ID = "0e1d8760bfdc62fdc1f4".freeze

      PRODUCTION = {
        alias: :github_prism,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, name: OAUTH_APP_NAME },
        inherits: [:first_party],
        capabilities: {
          access_internal_graphql_notifications: true,
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          subscribe_alive_events: true,
          proxima_first_party_sync: true,
          copilot_timeline_events: true,
          mobile_body_markup: true,
          verify_account_ownership: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          advanced_issue_search: true
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/hyperlist-mac"],
      }
    end
  end
end
