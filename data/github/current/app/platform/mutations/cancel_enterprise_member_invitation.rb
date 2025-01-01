# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CancelEnterpriseMemberInvitation < Platform::Mutations::Base
      description "Cancels a pending invitation for an unaffiliated member to join an enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :invitation_id, ID, "The Node ID of the pending enterprise member invitation.", required: true, loads: Objects::EnterpriseMemberInvitation

      field :invitation, Objects::EnterpriseMemberInvitation, "The invitation that was canceled.", null: true
      field :message, String, "A message confirming the result of canceling an member invitation.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, invitation:, **inputs)
        invitation.async_business.then do |business|
          permission.access_allowed?(
            :standard_authorization,
            permission: :manage_enterprise_members,
            resource: business,
            repo: nil,
            organization: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(invitation:, **inputs)
        ensure_business_can_use_api!(invitation&.business)

        if !invitation&.business&.can_invite_unaffiliated_user_accounts?
          raise Errors::Unprocessable.new("Enterprise member invitations are disabled in this environment")
        end

        viewer = context[:viewer]

        allowed = invitation.cancelable_by?(viewer) || viewer.site_admin?
        unless allowed
          raise Errors::Forbidden.new \
            "#{viewer.name} cannot cancel member invitations for #{invitation.business.name}."
        end

        invitation.cancel actor: viewer

        {
          invitation: invitation,
          message: "You've canceled #{invitation.email_or_invitee_name}'s invitation to become #{invitation.role_for_message} of #{invitation.business.name}.",
        }
      rescue ::BusinessAdministratorInvitation::AlreadyAcceptedError
        raise Errors::Unprocessable.new("This invitation has already been accepted.")
      end
    end
  end
end
