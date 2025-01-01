# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ConfirmEnterpriseOrganizationInvitation < Platform::Mutations::Base
      description "Confirms an accepted invitation for an organization to join an enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :invitation_id, ID, "The Node ID of the accepted enterprise organization invitation.", required: true, loads: Objects::EnterpriseOrganizationInvitation

      field :invitation, Objects::EnterpriseOrganizationInvitation, "The invitation that was confirmed.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, invitation:, **inputs)
        invitation.async_business.then do |business|
          permission.access_allowed?(:administer_business, resource: business,
            repo: nil, organization: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(invitation:, **inputs)
        ensure_business_can_use_api!(invitation&.business)
        business_full_plan_required!(invitation&.business)

        viewer = context[:viewer]
        business = invitation.business
        organization = invitation.invitee

        invitation.confirm(viewer)

        {
          invitation: invitation,
        }
      rescue BusinessOrganizationInvitation::ExpiredError
        raise Errors::Unprocessable.new("This invitation has expired.")
      rescue BusinessOrganizationInvitation::AlreadyConfirmedError
        raise Errors::Unprocessable.new("This invitation has already been confirmed.")
      rescue BusinessOrganizationInvitation::CanceledError
        raise Errors::Unprocessable.new("This invitation has been canceled.")
      rescue BusinessOrganizationInvitation::NotYetAcceptedError
        raise Errors::Unprocessable.new("This invitation has not yet been accepted.")
      rescue BusinessOrganizationInvitation::AlreadyBusinessMemberError
        raise Errors::Unprocessable.new("#{organization.display_login} is already part of an enterprise.")
      rescue BusinessOrganizationInvitation::InvalidActorError
        raise Errors::Unprocessable.new("#{viewer.display_login} cannot confirm this invitation on behalf of #{business.name}.")
      rescue BusinessOrganizationInvitation::InvalidInviterError
        raise Errors::Unprocessable.new("Please contact #{business.name}'s account representative to invite organizations.")
      rescue BusinessOrganizationInvitation::BusinessIsSpammyError
        raise Errors::Unprocessable.new("This enterprise has been flagged and cannot confirm organization invitations.")
      rescue BusinessOrganizationInvitation::BusinessIsTradeRestrictedError
        raise Errors::Unprocessable.new("This enterprise has been flagged and cannot confirm organization invitations.")
      rescue BusinessOrganizationInvitation::OrganizationIsTradeRestrictedError
        raise Errors::Unprocessable.new("#{organization.display_login} invitation cannot be confirmed because there's a problem with #{business.name}'s payment information.")
      rescue BusinessOrganizationInvitation::OrganizationHasOutstandingBalanceError
        raise Errors::Unprocessable.new(
          "#{organization.display_login} invitation cannot be confirmed because there's a problem with the payment information."
        )
      end
    end
  end
end
