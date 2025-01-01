# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class PrivateRegistrySecrets

      PRODUCTION = T.let({
        alias: :private_registry_secrets,
        database_lookup_attributes: { key: GitHub.private_registry_secrets_app_key },
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true,
        },
        properties: {
          audit_log_secrets_app_name: "private_registries",
          proxima_sync_delegate: :DefaultDelegate,
          secrets_event_subject: "integration",
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database-reviewers"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T.any(Symbol, T::Boolean)], T::Array[String])])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(:private_registry_secrets).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          key: GitHub.private_registry_secrets_app_key,
          name: "GitHub Private Registry Secrets",
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
