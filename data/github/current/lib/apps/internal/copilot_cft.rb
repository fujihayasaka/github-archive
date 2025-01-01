# typed: strict
# frozen_string_literal: true

module Apps
  class Internal
    class CopilotCFT
      extend T::Sig

      APP_NAME = "Copilot CFT"

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.integration_id_finder
        ->() {
          Integration.find_by(
            name: APP_NAME,
            owner_id: GitHub.trusted_apps_owner_id
          )&.id
        }
      end

      PRODUCTION = T.let({
        alias: :copilot_cft,
        id: integration_id_finder,
        inherits: [:internal],
        capabilities: {
          installed_globally: true,
          ip_allowlist_exempt: true,
          limited_access: false,
          proxima_first_party_sync: false, # We can enable this after dotcom is working
          user_installable: false,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-custom-model"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])
    end
  end
end
