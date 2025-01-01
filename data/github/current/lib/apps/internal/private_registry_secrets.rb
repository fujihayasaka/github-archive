# typed: strict
# frozen_string_literal: true

module Apps
  class Internal
    class PrivateRegistrySecrets
      extend T::Sig

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.id_finder
        ->() {
          Integration.find_by(key: GitHub.private_registry_secrets_app_key)&.id
        }
      end

      PRODUCTION = T.let({
        alias: :private_registry_secrets,
        id: id_finder,
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
        },
        can_auto_install: {},
        custom_instrumentation_events: {},
        owners: ["@github/advisory-database-reviewers"],
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T.any(Symbol, T::Boolean)], T::Array[String])])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Internal.integration(:private_registry_secrets).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          key: GitHub.private_registry_secrets_app_key,
          name: "GitHub Private Registry Secrets",
          url: "https://github.com",
          public: false,
          skip_generate_slug: true,
          skip_restrict_names_with_github_validation: true,
        }
        integration = Integration.create!(integration_attributes)

        Apps::Internal::Registry.instance.reload_caches!

        integration
      end
    end
  end
end
