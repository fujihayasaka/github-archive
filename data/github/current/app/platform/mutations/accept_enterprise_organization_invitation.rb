# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AcceptEnterpriseOrganizationInvitation < Platform::Mutations::Base
      description "Accepts a pending invitation for an organization to join an enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:org"]

      argument :invitation_id, ID, "The Node ID of the pending enterprise organization invitation.", required: true, loads: Objects::EnterpriseOrganizationInvitation
      argument :accept_terms_of_service_transfer, Boolean, "Confirm the acceptance of a transfer of the terms of service to the enterprise.", required: true

      field :invitation, Objects::EnterpriseOrganizationInvitation, "The invitation that was accepted.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, invitation:, **inputs)
        invitation.async_invitee.then do |org|
          permission.access_allowed?(:accept_business_organization_invitation,
            resource: org, repo: nil, organization: org,
            allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(invitation:, accept_terms_of_service_transfer:, **inputs)
        ensure_business_can_use_api!(invitation&.business)
        business_full_plan_required!(invitation&.business)

        viewer = context[:viewer]
        business = invitation.business
        organization = invitation.invitee

        raise Errors::Unprocessable.new("Please accept the transfer to #{business.name}.") unless accept_terms_of_service_transfer

        invitation.accept(viewer)

        {
          invitation: invitation,
        }
      rescue BusinessOrganizationInvitation::ExpiredError
        raise Errors::Unprocessable.new("This invitation has expired.")
      rescue BusinessOrganizationInvitation::InvalidActorError
        raise Errors::Unprocessable.new("#{viewer.display_login} cannot accept invitations on behalf of #{organization.display_login}.")
      rescue BusinessOrganizationInvitation::InvalidInviterError
        raise Errors::Unprocessable.new("Please contact #{business.name}'s account representative to invite organizations.")
      rescue BusinessOrganizationInvitation::AlreadyAcceptedError
        raise Errors::Unprocessable.new("This invitation has already been accepted.")
      rescue BusinessOrganizationInvitation::CanceledError
        raise Errors::Unprocessable.new("This invitation has been canceled.")
      rescue BusinessOrganizationInvitation::AlreadyBusinessMemberError
        raise Errors::Unprocessable.new("#{organization.display_login} is already part of an enterprise.")
      rescue BusinessOrganizationInvitation::InsufficientAvailableLicensesError
        raise Errors::Unprocessable.new("#{business.name} does not have sufficient licenses to add #{organization.display_login}.")
      rescue BusinessOrganizationInvitation::OrganizationHasOutstandingBalanceError
        raise Errors::Unprocessable.new(
          "This invitation cannot be accepted because #{organization.display_login} has an outstanding balance."
        )
      rescue BusinessOrganizationInvitation::BusinessIsTradeRestrictedError
        raise Errors::Unprocessable.new(
          "#{organization.display_login} invitation cannot be accepted because there's a problem with #{business.name}'s payment information."
        )
      rescue BusinessOrganizationInvitation::OrganizationIsTradeRestrictedError
        raise Errors::Unprocessable.new(
          "#{organization.display_login} invitation cannot be accepted because there's a problem with the payment information."
        )
      end
    end
  end
end
