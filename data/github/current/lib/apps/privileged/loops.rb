# typed: strict
# frozen_string_literal: true

module Apps
  class Privileged
    class Loops

      APP_NAME = "Copilot Loops"
      APP_ALIAS = :loops
      MAX_SESSION_TIME = T.let(30.minutes, Integer)
      MAX_REFRESH_TIME = T.let(1.day, Integer)

      PRODUCTION = T.let({
        database_lookup_attributes: { owner_id: :first_party_apps_owner_id, name: APP_NAME },
        alias: APP_ALIAS,
        inherits: [],
        capabilities: {
          danger_zone_permitted: false,
          installed_globally: true,
          proxima_first_party_sync: true,
          user_installable: false,
          enforce_internal_access_on_token_generation: true,
          limited_access: false,
        },
        properties: {
          proxima_sync_delegate: :DefaultDelegate,
          oauth_access_expiry: MAX_SESSION_TIME,
          refresh_token_expiry: MAX_REFRESH_TIME,
        },
        owners: ["@github/copilot-loops-reviewers"],
        # NOTE: these are required and expected to be hashes
        can_auto_install: {},
        custom_instrumentation_events: {
          create_scoped_installation: :skip,
        },
      }, T::Hash[Symbol, T.any(Proc, Symbol, T::Hash[Symbol, T::Boolean], T::Array[String])])

      # Since the application is a global app, you will need a manager of the app
      # on the GitHub organization to make live changes to the permissions.
      # Make sure to make the live changes way ahead of needing the permissions in production (at least 24h ahead)
      # Make sure to update the permissions below to reflect what's updated in the global app in production
      #
      # If no manager of the app is available, you can request it via a github/security-iam issue (#secure-access-engineering)
      PERMISSIONS = T.let({
        actions: :read,
        checks: :read,
        contents: :read,
        discussions: :read,
        issues: :read,
        metadata: :read,
        members: :read,
        pull_requests: :read,
        statuses: :read,
        organization_projects: :read,
        issue_types: :read,
      }, T::Hash[Symbol, Symbol])

      sig { returns(T.nilable(Integration)) }
      def self.seed_database!
        return if Apps::Privileged.integration(APP_ALIAS).present?

        integration_attributes = {
          owner: GitHub.first_party_apps_owner,
          name: APP_NAME,
          url: "https://github.com",
          visibility: :public_visibility,
          default_permissions: PERMISSIONS,
          skip_restrict_names_with_github_validation: true,
          skip_generate_slug: true,
        }

        # NOTE: we only need to hard-code the app ID for development
        # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        if Rails.env.development?
          integration_attributes[:id] = 837
        end

        Integration.create!(integration_attributes)
      end
    end
  end
end
