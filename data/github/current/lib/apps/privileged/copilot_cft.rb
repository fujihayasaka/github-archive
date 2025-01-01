# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotCFT

      APP_NAME = "Copilot CFT"

      PRODUCTION = T.let({
        alias: :copilot_cft,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        inherits: [:first_party],
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
