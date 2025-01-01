# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class CopilotByok
      PRODUCTION = T.let({
        alias: :copilot_byok,
        database_lookup_attributes: { key: GitHub.copilot_byok_app_key },
        inherits: [],
        capabilities: {
          attribution_only_system_identity: true, # We are only using this app for secret storage
          proxima_first_party_sync: true,
          user_installable: false, # We are only using this app for secret storage
        },
        properties: {
          audit_log_secrets_app_name: "copilot_byok",
          proxima_sync_delegate: :DefaultDelegate,
          secrets_event_subject: "copilot_byok",
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/github-models-reviewers"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T.any(Symbol, T::Boolean)], T::Array[String])])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(:copilot_byok).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          key: GitHub.copilot_byok_app_key,
          name: "Copilot BYOK",
          url: "https://github.com",
          visibility: :private_visibility,
          skip_generate_slug: true,
          skip_restrict_names_with_github_validation: true,
        }
        integration = Integration.create!(integration_attributes)

        Apps::Privileged::Registry.instance.reload_caches!

        integration
      end
    end
  end
end
