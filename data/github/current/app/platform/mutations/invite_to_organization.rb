# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class InviteToOrganization < Platform::Mutations::Base
      include GitHub::RateLimitable
      description "Invite a user to an organization"
      visibility :internal

      minimum_accepted_scopes ["admin:org"]

      argument :organization_id, ID, "The ID of the organization to invite the user to", required: true, loads: Objects::Organization
      argument :invitee_id, ID, "The ID of the user to invite", required: false, loads: Objects::User
      argument :email, String, "The email address of the user to invite", required: false
      argument :team_ids, [ID], "The IDs of the teams to add the user to as members", required: false, loads: Objects::Team
      argument :role, Enums::OrganizationInvitationRole, "The role to assign the user in the organization", required: false

      field :invitation, Objects::OrganizationInvitation, "The created invitation", null: true

      def resolve(organization:, invitee: nil, teams: [], **inputs)
        viewer = context[:viewer]
        actor  = context[:actor]
        email = inputs[:email].presence
        role = (inputs[:role] || :direct_member).to_sym

        if GitHub.bypass_org_invites_enabled?
          raise Errors::Unprocessable.new("Organization invitations are disabled")
        end

        if actor.can_have_granular_permissions?
          if !organization.resources.members.writable_by?(actor)
            raise Errors::Forbidden.new("Inviter can not invite members to this organization")
          end
        else
          # User must be an admin of the organization
          unless organization.adminable_by?(viewer)
            raise Errors::Forbidden.new("Inviter must be an organization admin")
          end
        end

        # Must obey rate limits
        limit_policy = OrganizationInvitation::RateLimitPolicy.new(organization)
        limit_key = "orgs/invitations.new:org-#{organization.id}"
        if rate_limit_increment(limit_key, { max_tries: limit_policy.limit, ttl: limit_policy.ttl }).at_limit?
          raise Errors::Forbidden.new("Over invitation rate limit")
        end

        # If the user has opted out, present a generic error message
        if OrganizationInvitation::OptOut.opted_out?(org: organization, email: email, invitee: invitee)
          raise Errors::Unprocessable.new("The request could not be processed")
        end

        # Deliberately generic error
        if invitee&.is_enterprise_managed?
          raise Errors::Unprocessable.new("Invitee cannot be invited to this organization")
        end

        begin
          invitation = organization.invite(invitee, inviter: viewer, role: role, email: email, teams: teams || [], invitation_source: :member)
        rescue OrganizationInvitation::InvalidError, OrganizationInvitation::NoAvailableSeatsError, ActiveRecord::RecordInvalid, OrganizationInvitation::TradeControlsError => error
          raise Errors::Unprocessable.new(error.message)
        end

        { invitation: invitation }
      end
    end
  end
end
