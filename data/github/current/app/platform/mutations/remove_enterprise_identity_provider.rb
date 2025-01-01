# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveEnterpriseIdentityProvider < Platform::Mutations::Base
      description "Removes the identity provider from an enterprise. Owners of enterprises both with and without Enterprise Managed Users may use this mutation."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise from which to remove the identity provider.", required: true, loads: Objects::Enterprise

      field :identity_provider, Objects::EnterpriseIdentityProvider, "The identity provider that was removed from the enterprise.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_not_suspended!(enterprise)

        actor = context[:actor]
        viewer = context[:viewer]

        if !actor.site_admin? && !enterprise.owner?(actor)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to remove the identity provider from this enterprise.")
        end

        provider = enterprise.saml_provider
        provider&.destroy

        { identity_provider: provider }
      end
    end
  end
end
