# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class Spark

      APP_NAME = "Copilot Spark"
      APP_ALIAS = :spark

      PRODUCTION = T.let({
        id: ->() {},
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        alias: APP_ALIAS,
        inherits: [:first_party],
        capabilities: {
          installed_globally: true,
          user_installable: false,
          limited_access: false,
          bypass_github_models_authorization: true,
        },
        owners: ["@github/copilot-workbench-reviewers"],
        # NOTE: these are required and expected to be hashes
        properties: {},
        can_auto_install: {},
        custom_instrumentation_events: {
          create_installation: :skip,
          create_scoped_installation: :skip,
        },
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      PERMISSIONS = T.let({
        user_models: :read,
      }, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(APP_ALIAS).present?

        integration_attributes = {
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          url: "https://github.com",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }

        # app ID needs to be hardcoded in dev for CAPI
        # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        if Rails.env.development?
          integration_attributes[:id] = 924
        end

        integration = Integration.create!(integration_attributes)

        Apps::Privileged::Registry.instance.reload_caches!

        integration
      end
    end
  end
end
