# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotCLI

      PRODUCTION = T.let({
        alias: :copilot_cli,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, key: GitHub.copilot_cli_app_key },
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-cli"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])
    end
  end
end
