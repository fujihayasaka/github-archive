# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CompleteEnterpriseOrganizationInvitation < Platform::Mutations::Base
      description "Marks a confirmed invitation for an organization to join an enterprise as completed."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :invitation_id, ID, "The Node ID of the confirmed enterprise organization invitation.", required: true, loads: Objects::EnterpriseOrganizationInvitation

      field :invitation, Objects::EnterpriseOrganizationInvitation, "The invitation that was completed.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, invitation:, **inputs)
        viewer = permission.viewer
        viewer.site_admin?
      end

      def resolve(invitation:, **inputs)
        ensure_business_can_use_api!(invitation&.business)
        business_full_plan_required!(invitation&.business)

        viewer = context[:viewer]
        business = invitation.business
        organization = invitation.invitee

        invitation.complete(viewer)

        {
          invitation: invitation,
        }
      rescue BusinessOrganizationInvitation::CanceledError
        raise Errors::Unprocessable.new("This invitation has been canceled.")
      rescue BusinessOrganizationInvitation::NotYetConfirmedError
        raise Errors::Unprocessable.new("This invitation has not yet been confirmed.")
      rescue BusinessOrganizationInvitation::AlreadyCompletedError
        raise Errors::Unprocessable.new("This invitation has already been completed.")
      rescue BusinessOrganizationInvitation::InvalidActorError
        raise Errors::Unprocessable.new("#{viewer.name} cannot complete this invitation.")
      end
    end
  end
end
