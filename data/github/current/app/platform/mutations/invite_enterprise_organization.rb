# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class InviteEnterpriseOrganization < Platform::Mutations::Base
      description "Invite an organization to join an enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise to which you want to invite an organization.", required: true, loads: Objects::Enterprise
      argument :organization_id, ID, "The ID of the organization to invite to join the enterprise.", required: true, loads: Objects::Organization

      field :invitation, Objects::EnterpriseOrganizationInvitation, "The created enterprise organization invitation", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, organization:, **inputs)
        ensure_business_can_use_api!(enterprise)
        business_full_plan_required!(enterprise)

        viewer = context[:viewer]

        unless GitHub.business_organization_invitations_available?
          raise Errors::Unprocessable.new("Enterprise organization invitations are disabled in this environment.")
        end

        begin
          invitation = ::BusinessOrganizationInvitation.create! \
            business: enterprise, inviter: viewer, invitee: organization
        rescue ActiveRecord::RecordInvalid => error
          raise Errors::Unprocessable.new error.record.errors.full_messages.first
        end

        { invitation: invitation }
      end
    end
  end
end
