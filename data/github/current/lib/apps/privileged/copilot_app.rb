# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotApp
      PRODUCTION = T.let({
        alias: :copilot_app,
        database_lookup_attributes: { user_id: :first_party_apps_owner_id, key: GitHub.copilot_app_key },
        inherits: [],
        capabilities: {
          access_pull_request_diff_graphql_api: ->(_app) { FeatureFlag.vexi.enabled?(:github_app_enable_pull_request_diff_capability, default: false) },
          access_pull_request_mergebox_graphql_api: ->(_app) { FeatureFlag.vexi.enabled?(:github_app_enable_mergebox_capability, default: false) },
          organization_oauth_app_policy_exempt: true,
          proxima_first_party_sync: true,
          oauth_token_via_entra_exchange: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/github-app"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])
    end
  end
end
