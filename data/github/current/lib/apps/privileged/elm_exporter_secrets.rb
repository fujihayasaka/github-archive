# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class ElmExporterSecrets

      PRODUCTION = T.let({
        alias: :elm_exporter_secrets,
        database_lookup_attributes: { key: GitHub.elm_exporter_secrets_app_key, owner_id: :first_party_apps_owner_id },
        inherits: [],
        capabilities: {
          attribution_only_system_identity: true, # We are only using this app for secret storage
          user_installable: false, # We are only using this app for secret storage
          proxima_first_party_sync: true, # Sync this app with Proxima stamps
        },
        properties: {
          audit_log_secrets_app_name: "elm_exporter_secrets",
          secrets_event_subject: "integration",
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/migrations-vnext"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T.any(Symbol, T::Boolean)], T::Array[String])])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(:elm_exporter_secrets).present?

        integration_attributes = {
          owner: GitHub.first_party_apps_owner,
          key: GitHub.elm_exporter_secrets_app_key,
          name: "ELM Exporter Secrets",
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
