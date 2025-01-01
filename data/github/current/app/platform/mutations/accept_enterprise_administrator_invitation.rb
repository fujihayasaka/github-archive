# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AcceptEnterpriseAdministratorInvitation < Platform::Mutations::Base
      description "Accepts a pending invitation for a user to become an administrator of an enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      scopeless_tokens_as_minimum

      argument :invitation_id, ID, "The id of the invitation being accepted", required: true, loads: Objects::EnterpriseAdministratorInvitation

      field :invitation, Objects::EnterpriseAdministratorInvitation, "The invitation that was accepted.", null: true
      field :message, String, "A message confirming the result of accepting an administrator invitation.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, invitation:)
        invitation.async_business.then do |_business|
          next true if invitation.email.present?
          permission.viewer.is_a?(User) && permission.viewer.id == invitation.invitee_id
        end
      end

      def resolve(invitation:)
        ensure_business_can_use_api!(invitation&.business)

        invitation.accept acceptor: context[:viewer]

        {
          invitation: invitation,
          message: "You are now #{invitation.role_for_message} of #{invitation.business.name}.",
        }

      rescue BusinessAdministratorInvitation::ExpiredError
        raise Errors::Unprocessable.new("This invitation has already expired.")
      rescue BusinessAdministratorInvitation::CanceledError
        raise Errors::Unprocessable.new("This invitation has been canceled.")
      rescue BusinessAdministratorInvitation::AlreadyAcceptedError
        raise Errors::Unprocessable.new("This invitation has already been accepted.")
      rescue BusinessAdministratorInvitation::InvalidAcceptorError
        raise Errors::Unprocessable.new("Viewer cannot accept an invitation when they are not the invitee.")
      rescue BusinessAdministratorInvitation::AcceptorAlreadyOwnerError
        raise Errors::Unprocessable.new("This invitation cannot be accepted by an existing enterprise owner.")
      rescue Business::UserHasNoExternalIdentityError
        raise Errors::Unprocessable.new("This invitation cannot be accepted because the user does not have a linked external identity.")
      end
    end
  end
end
