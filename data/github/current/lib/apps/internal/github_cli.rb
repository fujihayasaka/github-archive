# typed: true
# frozen_string_literal: true

module Apps
  class Internal
    class GitHubCLI
      OAUTH_APP_NAME = "GitHub CLI"
      GITHUB_CLI_CLIENT_ID = "178c6fc778ccc68e1d6a".freeze

      def self.id_finder(name)
        ->() {
          OauthApplication.find_by(
            user_id: GitHub.trusted_apps_owner_id,
            name: name,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :github_cli,
        id: id_finder(OAUTH_APP_NAME),
        inherits: [:internal],
        capabilities: {
          access_internal_graphql_notifications: true,
          blockable_first_party_client: true,
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          enqueue_mergeable_update: true,
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          proxima_first_party_sync: true,
          verify_account_ownership: true # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/cli"],
      }
    end
  end
end
