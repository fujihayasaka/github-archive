# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CancelEnterpriseOrganizationInvitation < Platform::Mutations::Base
      description "Cancels a pending invitation for an organization to join an enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise", "admin:org"]

      argument :invitation_id, ID, "The Node ID of the pending enterprise organization invitation.", required: true, loads: Objects::EnterpriseOrganizationInvitation

      field :invitation, Objects::EnterpriseOrganizationInvitation, "The invitation that was canceled.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, invitation:, **inputs)
        invitation.async_invitee.then do |org|
          permission.access_allowed?(:cancel_business_organization_invitation,
            resource: invitation, repo: nil, organization: org,
            allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(invitation:, **inputs)
        ensure_business_can_use_api!(invitation&.business)
        business_full_plan_required!(invitation&.business)

        viewer = context[:viewer]
        invitation.cancel(viewer)

        { invitation: invitation }
      rescue BusinessOrganizationInvitation::ExpiredError
        raise Errors::Unprocessable.new("This invitation has expired.")
      rescue BusinessOrganizationInvitation::InvalidActorError
        raise Errors::Unprocessable.new("#{viewer.name} cannot cancel invitations on behalf of #{invitation.invitee.name}.")
      rescue BusinessOrganizationInvitation::AlreadyConfirmedError
        raise Errors::Unprocessable.new("This invitation has already been confirmed.")
      rescue BusinessOrganizationInvitation::CanceledError
        raise Errors::Unprocessable.new("This invitation has already been canceled.")
      end
    end
  end
end
