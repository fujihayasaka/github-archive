# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class Neutron

      APP_NAME = "GitHub Models"
      APP_ALIAS = :neutron
      MAX_SESSION_TIME = T.let(30.minutes, Integer)
      MAX_REFRESH_TIME = T.let(1.day, Integer)

      PRODUCTION = T.let({
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, key: GitHub.github_models_app_key },
        alias: APP_ALIAS,
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true,
          user_installable: false,
          oauth_authorizations_revocable_by_user: false,
          bypass_github_models_authorization: true,
          auto_upgrade_permissions: true,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
          oauth_access_expiry: MAX_SESSION_TIME,
          refresh_token_expiry: MAX_REFRESH_TIME,
        },
        owners: ["@github/github-models-reviewers"],
        # NOTE: these are required and expected to be hashes
        can_auto_install: {},
        custom_instrumentation_events: {},
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      PERMISSIONS = T.let({}, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(APP_ALIAS).present?

        Integration.create!({
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          key: GitHub.github_models_app_key,
          url: "https://github.com",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        })
      end
    end
  end
end
