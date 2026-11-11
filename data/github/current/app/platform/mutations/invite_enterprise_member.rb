# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class InviteEnterpriseMember < Platform::Mutations::Base
      description "Invite someone to become an unaffiliated member of the enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise to which you want to invite an unaffiliated member.", required: true, loads: Objects::Enterprise
      argument :invitee, String, "The login of a user to invite as an unaffiliated member.", required: false
      argument :email, String, "The email of the person to invite as an unaffiliated member.", required: false

      field :invitation, Objects::EnterpriseMemberInvitation, "The created enterprise member invitation.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(
          :standard_authorization,
          permission: :manage_enterprise_members,
          resource: enterprise,
          repo: nil,
          organization: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      def resolve(enterprise:, **inputs)
        ensure_business_can_use_api!(enterprise)

        if enterprise.enterprise_managed_user_enabled?
          raise Errors::Forbidden.new("This enterprise is an IdP managed enterprise.  Invitations can only be sent through an IdP.")
        end

        viewer = context[:viewer]

        if GitHub.bypass_business_member_invites_enabled? || !enterprise.can_invite_unaffiliated_user_accounts?
          raise Errors::Unprocessable.new("Enterprise member invitations are disabled in this environment")
        end

        if inputs[:invitee].present?
          raise Errors::Unprocessable.new("Invalid user login: #{inputs[:invitee]}") if inputs[:invitee].include?("_")
          invitee = Loaders::ActiveRecord.load(::User, inputs[:invitee], column: :login).sync
          raise Errors::NotFound.new("Could not find invitee with login: #{inputs[:invitee]}") unless invitee
        else
          email = inputs[:email]
        end

        begin
          invitation = if invitee.present?
            enterprise.invite_unaffiliated_member user: invitee, inviter: viewer
          else
            enterprise.invite_unaffiliated_member email: email, inviter: viewer
          end
        rescue BusinessAdministratorInvitation::AlreadyAcceptedError, BusinessAdministratorInvitation::InvalidError, ActiveRecord::RecordInvalid => error
          raise Errors::Unprocessable.new error
        end

        { invitation: invitation }
      end
    end
  end
end
