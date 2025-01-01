# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all configuration settings
    # related to first-party apps (those apps owned and operated by GitHub).
    module FirstPartyApps

      # The canonical Organization#login of the entity that owns first-party (internal)
      # GitHub and Oauth apps:
      #
      # - In github.com this is the @github organization
      # - In GHES (single-tenant enterprise) this is the @github-enterprise
      # organization
      # - In Proxima (multi-tenant enterprise) this is the @github-enterprise
      # organization
      def first_party_apps_org_name
        if GitHub.single_tenant_enterprise? || GitHub.multi_tenant_enterprise?
          "github-enterprise"
        else
          "github"
        end
      end
      alias_method :trusted_oauth_apps_org_name, :first_party_apps_org_name

      # Find the Organization that owns First Party OAuth and GitHub Apps.
      # This Organization is expected to exist already.
      #
      # Returns an Organization or nil
      def first_party_apps_owner
        # Use Organization.unscoped to avoid inheriting any temporary scopes.
        # For example, in the following code:
        #
        #     current_user.organizations.oauth_app_policy_met_by(current_app)
        #
        # Organization.find_by_login("github") runs this query:
        #
        #     SELECT `users`.*
        #       FROM `users`
        #       WHERE `users`.`type` IN ('Organization') AND
        #             `users`.`id` IN (<current_user.id>) AND
        #             `users`.`login` = 'github'
        #       LIMIT 1
        #
        # and Organization.unscoped.find_by_login runs this query:
        #
        #    SELECT `users`.*
        #      FROM `users`
        #      WHERE `users`.`type` IN ('Organization') AND
        #            `users`.`login` = 'github'
        #      LIMIT 1
        Organization.unscoped.find_by_login(trusted_oauth_apps_org_name)
      end
      alias_method :trusted_oauth_apps_owner, :first_party_apps_owner

      # The database ID of the trusted Apps owner (the GitHub organization). This
      # value is memoized (unlike `first_party_apps_owner`) because the value
      # should never change during the lifetime of a Rails process.
      #
      # Returns an Integer or nil.
      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def first_party_apps_owner_id
        @first_party_apps_owner_id ||= first_party_apps_owner&.id
      end
      alias_method :trusted_apps_owner_id, :first_party_apps_owner_id

      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
      def first_party_apps_owner_id=(id)
        @first_party_apps_owner_id = id
      end
      alias_method :trusted_apps_owner_id=, :first_party_apps_owner_id=


      def trusted_proxima_apps_owner_name
        "ProximaIntegrations"
      end

      # Find the trusted organization that owns internal Apps used to allow
      # Proxima access back to Dotcom. Should only exist on Dotcom.
      def trusted_proxima_apps_owner
        Organization.unscoped.find_by_login(trusted_proxima_apps_owner_name)
      end
    end
  end

  extend Config::FirstPartyApps
end
