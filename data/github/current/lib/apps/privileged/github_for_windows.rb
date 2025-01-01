# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GitHubForWindows
      GITHUB_WINDOWS_CLIENT_ID = "fd5f729d309a7bfa8e1b".freeze

      PRODUCTION = {
        alias: :github_for_windows,
        id: ->() {
          OauthApplication.find_by(key: GITHUB_WINDOWS_CLIENT_ID)&.id
        },
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
