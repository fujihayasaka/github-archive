# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveEnterpriseOrganization < Platform::Mutations::Base
      description "Removes an organization from the enterprise"

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise from which the organization should be removed.", required: true, loads: Objects::Enterprise
      argument :organization_id, ID, "The ID of the organization to remove from the enterprise.", required: true, loads: Objects::Organization

      field :enterprise, Objects::Enterprise, "The updated enterprise.", null: true
      field :organization, Objects::Organization, "The organization that was removed from the enterprise.", null: true
      field :viewer, Objects::User, "The viewer performing the mutation.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(
          :standard_authorization,
          permission: :remove_enterprise_organizations,
          resource: enterprise,
          repo: nil,
          organization: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      def resolve(enterprise:, organization:, **inputs)
        if GitHub.single_business_environment?
          raise Errors::Forbidden.new("Organizations cannot be removed from the global enterprise in this environment.")
        end

        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        if organization.enterprise_managed_user_enabled?
          raise Errors::Forbidden.new("Organizations can't be removed from an externally managed enterprise.")
        end

        viewer = context[:viewer]

        unless enterprise.actor_can_remove_organizations?(viewer)
          unless enterprise.owner?(viewer)
            raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to remove an organization from this enterprise.")
          end

          raise Errors::Unprocessable.new("Please contact sales to modify #{enterprise.name}.")
        end

        membership = enterprise.organization_memberships.where organization: organization
        unless membership.any?
          raise Errors::Unprocessable.new("Organization #{organization.display_login} doesn't belong to #{enterprise.name}.")
        end

        enterprise.remove_organization(organization, actor: viewer)

        {
          enterprise: enterprise,
          organization: organization,
          viewer: viewer,
        }
      end
    end
  end
end
