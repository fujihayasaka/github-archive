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
          organization_oauth_app_policy_exempt: true,
          proxima_first_party_sync: true,
          subscribe_limited_user: true,
          oauth_token_via_entra_exchange: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-cli"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      GITHUB_APP = T.let({
        alias: :copilot_cli_github_app,
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, key: GitHub.copilot_cli_github_app_key },
        inherits: [:first_party],
        capabilities: {
          proxima_first_party_sync: true,
          is_copilot: true,
        },
        properties: {
          display_login: "Copilot",
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/copilot-cli"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        existing_app = Apps::Privileged.integration(:copilot_cli_github_app)
        return existing_app if existing_app.present?

        integration_attributes = {
          owner: GitHub.first_party_apps_owner,
          key: GitHub.copilot_cli_github_app_key,
          name: "copilot cli",
          slug: "copilot-developer-cli",
          url: "https://github.com/",
          visibility: :public_visibility,
          default_permissions: {},
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }
        integration = Integration.create!(integration_attributes)

        Apps::Privileged::Registry.instance.reload_caches!

        integration
      end
    end
  end
end
