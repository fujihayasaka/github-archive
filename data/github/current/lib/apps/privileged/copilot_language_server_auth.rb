# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotLanguageServerAuth

      PRODUCTION = T.let({
        alias: :copilot_language_server_auth,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, key: GitHub.copilot_language_server_auth_app_key },
        inherits: [],
        capabilities: {
          blockable_first_party_client: true,
          generate_copilot_cdn_token: true,
          organization_oauth_app_policy_exempt: true,
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
