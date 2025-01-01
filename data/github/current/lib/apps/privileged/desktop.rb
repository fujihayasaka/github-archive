# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class Desktop
      APP_NAME = "GitHub Desktop"
      GITHUB_DESKTOP_CLIENT_ID = "de0e3c7e9973e1c4dd77".freeze
      GITHUB_DESKTOP_DEVELOPMENT_CLIENT_ID = "3a723b10ac5575cc5bb9".freeze

      PRODUCTION = {
        alias: :github_desktop,
        id: ->() {
          OauthApplication.find_by(key: GITHUB_DESKTOP_CLIENT_ID)&.id
        },
        inherits: [:first_party],
        capabilities: {
          access_desktop_internal: true,
          authorizations_via_rest_api_restricted: true,
          blockable_first_party_client: true,
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          oauth_checks_access: true,
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          proxima_first_party_sync: true,
          subscribe_alive_events: true,
          verify_account_ownership: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          access_copilot_limited_graphql_api: true, # Allows this app to access GraphQL APIs related to Copilot Free quotas and limits
          copilot_desktop: true, # Allows this app to access general Copilot Desktop APIs
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/desktop"],
      }

      DEVELOPMENT = {
        alias: :github_desktop_development,
        id: ->() {
          OauthApplication.find_by(key: GITHUB_DESKTOP_DEVELOPMENT_CLIENT_ID)&.id
        },
        inherits: [:first_party],
        capabilities: {
          access_desktop_internal: true,
          authorizations_via_rest_api_restricted: true,
          blockable_first_party_client: false,
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          oauth_checks_access: true,
          organization_oauth_app_policy_exempt: false,
          proxima_first_party_sync: true,
          subscribe_alive_events: true,
          verify_account_ownership: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          access_copilot_limited_graphql_api: true, # Allows this app to access GraphQL APIs related to Copilot Free quotas and limits
          copilot_desktop: true, # Allows this app to access general Copilot Desktop APIs
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/desktop"],
      }

      def self.app_ids
        @desktop_app_ids ||= Apps::Privileged.oauth_application_ids([:github_desktop, :github_desktop_development]).values.compact
      end
    end
  end
end
