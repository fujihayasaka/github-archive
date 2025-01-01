# typed: strict
# frozen_string_literal: true

module Apps
  class Internal
    class Neutron
      extend T::Sig

      APP_NAME = "GitHub Neutron"
      APP_ALIAS = :neutron
      MAX_SESSION_TIME = T.let(30.minutes, Integer)
      MAX_REFRESH_TIME = T.let(1.day, Integer)

      sig { returns(T.proc.returns(T.nilable(Integer))) }
      def self.integration_id_finder
        ->() {
          Integration.find_by(
            name: APP_NAME,
            owner_id: GitHub.trusted_apps_owner_id
          )&.id
        }
      end

      PRODUCTION = T.let({
        id: integration_id_finder,
        alias: APP_ALIAS,
        inherits: [],
        capabilities: {
          proxima_first_party_sync: true,
          user_installable: false,
          oauth_authorizations_revocable_by_users: false,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
          oauth_access_expiry: MAX_SESSION_TIME,
          refresh_token_expiry: MAX_REFRESH_TIME,
        },
        owners: ["@github/neutron-reviewers"],
        # NOTE: these are required and expected to be hashes
        can_auto_install: {},
        custom_instrumentation_events: {},
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      PERMISSIONS = T.let({}, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Internal.integration(APP_ALIAS).present?

        Integration.create!({
          owner: GitHub.trusted_oauth_apps_owner,
          name: APP_NAME,
          url: "https://github.com",
          public: true,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        })
      end
    end
  end
end
