# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotXcodeLanguageServerAuth

      PRODUCTION = T.let({
        alias: :copilot_xcode_language_server_auth,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, key: GitHub.copilot_xcode_language_server_auth_app_key },
        inherits: [],
        capabilities: {
          generate_copilot_cdn_token: true,
        },
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-editor-team"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])
    end
  end
end
