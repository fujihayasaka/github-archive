# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class GCMCore
      GCMCORE_CLIENT_ID = "0120e057bd645470c1ed".freeze

      def self.id_finder
        ->() {
          OauthApplication.find_by(
            key: GCMCORE_CLIENT_ID,
          )&.id
        }
      end

      PRODUCTION = {
        alias: :gcm_core,
        id: id_finder,
        inherits: [],
        capabilities: {
          blockable_first_party_client: true,
          create_tokens_for_ssh_key_verification: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
          operated_by_github: true, # Preserves behavior that used to be hard-coded in `OauthApplication`
          organization_oauth_app_policy_exempt: true, # Preserves behavior that used to be inherited from `OauthApplication::CLIENT_APPS_IDS`
          proxima_first_party_sync: true,
          verify_account_ownership: true, # Preserves behavior that used to be hard-coded in `OauthApplication#github_desktop?`
        },

        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/git-systems"],
      }
    end
  end
end
