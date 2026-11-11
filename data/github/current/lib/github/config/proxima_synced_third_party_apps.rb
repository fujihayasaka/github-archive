# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all configuration settings
    # related to third-party apps (those apps not owned or operated by GitHub) synced to Proxima.
    module ProximaSyncedThirdPartyApps
      # The canonical Organization#login of the entity that owns synced third-party
      # GitHub and Oauth apps in Proxima:
      #
      # - In Proxima (multi-tenant enterprise) this is a special non-enterprise
      # managed organization, akin to the @github-enterprise organization,
      # which lives outside of any tenant context.
      sig { returns(String) }
      def proxima_third_party_apps_owner_login
        "github-third-party-apps-owner"
      end

      def proxima_third_party_apps_owner
        return nil unless GitHub.multi_tenant_enterprise?

        Organization.unscoped.find_by_login(proxima_third_party_apps_owner_login)
      end

      def proxima_third_party_apps_owner_id
        return @proxima_third_party_apps_owner_id if defined?(@proxima_third_party_apps_owner_id)

        @proxima_third_party_apps_owner = proxima_third_party_apps_owner&.id
      end

      def proxima_third_party_apps_owner_id=(id)
        @proxima_third_party_apps_owner_id = id
      end

      def proxima_third_party_apps_path_prefix
        "third-party-apps"
      end

      def proxima_external_apps_owner_slug
        "external-app"
      end
    end
  end

  extend Config::ProximaSyncedThirdPartyApps
end
