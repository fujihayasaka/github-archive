# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseOwnerOrganizationRole < Platform::Mutations::Base
      description "Updates the role of an enterprise owner with an organization."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the Enterprise which the owner belongs to.", required: true, loads: Objects::Enterprise
      argument :organization_id, ID, "The ID of the organization for membership change.", required: true, loads: Objects::Organization
      argument :organization_role, Enums::RoleInOrganization, "The role to assume in the organization.", required: true

      field :message, String, "A message confirming the result of changing the owner's organization role.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, organization:, **inputs)
        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        viewer = context[:viewer]


        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to perform this action on this enterprise.")
        end

        business_owner = Organization::BusinessOwner.new(
          organization: organization,
          business_owner: viewer)

        unless business_owner.business_owner?
          raise Errors::Forbidden.new("Could not perform this action on organization with the ID '#{organization.id}'.")
        end

        status = business_owner.change_role(inputs[:organization_role])

        if status.error?
          raise Errors::Unprocessable.new(status.message)
        end

        case inputs[:organization_role]
        when "unaffiliated"
          { message: "#{viewer.display_login} was removed from the organization." }
        else
          { message: "#{viewer.display_login}'s role was set to #{inputs[:organization_role].humanize.downcase}." }
        end
      end
    end
  end
end
