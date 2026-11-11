# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class InviteEnterpriseAdmin < Platform::Mutations::Base
      description "Invite someone to become an administrator of the enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise to which you want to invite an administrator.", required: true, loads: Objects::Enterprise
      argument :invitee, String, "The login of a user to invite as an administrator.", required: false
      argument :email, String, "The email of the person to invite as an administrator.", required: false
      argument :role, Enums::EnterpriseAdministratorRole, "The role of the administrator.", required: false

      field :invitation, Objects::EnterpriseAdministratorInvitation, "The created enterprise administrator invitation.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(
          :standard_authorization,
          permission: :manage_enterprise_admins,
          resource: enterprise,
          repo: nil,
          organization: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_can_use_api!(enterprise)

        if enterprise.enterprise_managed_user_enabled?
          raise Errors::Forbidden.new("This enterprise is an IdP managed enterprise.  Administrative roles can only be changed through an IdP.")
        end

        if GitHub.bypass_business_member_invites_enabled?
          raise Errors::Unprocessable.new("Enterprise owner invitations are disabled in this environment")
        end

        viewer = context[:viewer]


        unless enterprise.actor_can_manage_admins?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to admin this enterprise.")
        end

        if inputs[:invitee].present?
          invitee = Loaders::ActiveRecord.load(::User, inputs[:invitee], column: :login).sync
          raise Errors::NotFound.new("Could not find invitee with login: #{inputs[:invitee]}") unless invitee
        else
          email = inputs[:email]
        end

        begin
          invitation = if invitee.present?
            enterprise.invite_admin user: invitee, inviter: viewer, role: inputs[:role]
          else
            enterprise.invite_admin email: email, inviter: viewer, role: inputs[:role]
          end
        rescue BusinessAdministratorInvitation::AlreadyAcceptedError, BusinessAdministratorInvitation::InvalidError, ActiveRecord::RecordInvalid => error
          raise Errors::Unprocessable.new error
        end

        { invitation: invitation }
      end
    end
  end
end
