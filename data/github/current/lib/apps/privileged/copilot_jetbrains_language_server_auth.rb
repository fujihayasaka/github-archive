# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotJetBrainsLanguageServerAuth

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.integration_id_finder
        ->() {
          Integration.find_by(
            key: GitHub.copilot_jetbrains_language_server_auth_app_key,
            owner_id: GitHub.first_party_apps_owner_id
          )&.id
        }
      end

      PRODUCTION = T.let({
        alias: :copilot_jetbrains_language_server_auth,
        id: integration_id_finder,
        inherits: [],
        capabilities: {
          generate_copilot_cdn_token: true,
          proxima_first_party_sync: true
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-editor-team"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])
    end
  end
end
