# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotIntellijPlugin
      # Managing a transition to a more generic app name that can be used
      # by things other than IntelliJ.
      OLD_APP_NAME = "copilot-intellij"
      NEW_APP_NAME = "GitHub Copilot Plugin"

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.integration_id_finder
        ->() {
          Integration.where(
            name: [OLD_APP_NAME, NEW_APP_NAME],
            owner_id: GitHub.trusted_apps_owner_id
          ).first&.id
        }
      end

      PRODUCTION = T.let({
        alias: :copilot_intellij_plugin,
        id: integration_id_finder,
        inherits: [:first_party],
        capabilities: {
          generate_copilot_cdn_token: true,
          proxima_first_party_sync: true,
          user_installable: false # This App only needs to authorize a user and generate a Copilot HMAC token
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/octo-cit-reviewers"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])
    end
  end
end
