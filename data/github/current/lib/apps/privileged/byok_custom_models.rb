# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class ByokCustomModels

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.id_finder
        ->() {
          Integration.find_by(key: GitHub.byok_custom_models_app_key)&.id
        }
      end

      PRODUCTION = T.let({
        alias: :byok_custom_models,
        id: id_finder,
        database_lookup_attributes: { key: GitHub.byok_custom_models_app_key },
        inherits: [],
        capabilities: {
          attribution_only_system_identity: true, # We are only using this app for secret storage
          user_installable: false, # We are only using this app for secret storage
        },
        properties: {
          audit_log_secrets_app_name: "github_models_byok",
          secrets_event_subject: "byok",
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/github-models-reviewers"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T.any(Symbol, T::Boolean)], T::Array[String])])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(:byok_custom_models).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          key: GitHub.byok_custom_models_app_key,
          name: "GitHub Models BYOK",
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
