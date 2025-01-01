# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-organizations"

module Api::Internal::Twirp::Classroom
  module Organizations
    module V1
      # Handler for the MonolithTwirp::Classroom::Organizations::V1::OrganizationsAPIService
      class OrganizationsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        connected_to_writing_for :update_organization, :add_user_to_organization
        handles_service MonolithTwirp::Classroom::Organizations::V1::OrganizationsAPIService

        # Public: Implementation of the GetOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Organizations::V1::GetOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Organizations::V1::GetOrganizationResponse, or a Twirp::Error.
        def get_organization(req, env)
          unless organization_id = id_argument(req.org_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "org_id")
          end

          unless organization = Organization.find_by(id: organization_id)
            return Twirp::Error.not_found("organization does not exist", argument: "org_id")
          end

          {
            login: organization.login,
            id: organization.id,
            avatar_url: organization.primary_avatar_url,
            html_url: organization.permalink,
            name: organization.name,
            node_id: organization.global_relay_id,
            can_members_fork_private_repositories: organization.allow_private_repository_forking?,
          }
        end

        # Public: Implementation of the UpdateOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Organizations::V1::UpdateOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Organizations::V1::UpdateOrganizationResponse, or a Twirp::Error.
        def update_organization(req, env)
          unless organization_id = id_argument(req.org_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "org_id")
          end

          unless organization = Organization.find_by(id: organization_id)
            return Twirp::Error.not_found("organization does not exist", argument: "org_id")
          end

          # Enable private repository forking if the organization allows it
          if req.can_members_fork_private_repositories && !organization.allow_private_repository_forking?
            enabled = organization.allow_private_repository_forking(actor: organization.admins.first)
            return Twirp::Error.permission_denied("Private repository forking could not be enabled") unless enabled
          end

          { success: true }
        end

        # Public: Implementation of the ConfirmOrganizationExists Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Organizations::V1::ConfirmOrganizationExistsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Organizations::V1::ConfirmOrganizationExistsResponse, or a Twirp::Error.
        def confirm_organization_exists(req, env)
          organization_id = id_argument(req.organization_id)

          unless organization_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          organization = Organization.find_by(id: organization_id)

          if organization
            { organization_id: organization.id, org_exists: true, reason: "" }
          else
            { organization_id: organization_id, org_exists: false, reason: "organization not found" }
          end
        end

        # Public: Implementation of the AddUserToOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Organizations::V1::AddUserToOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Organizations::V1::AddUserToOrganizationResponse, or a Twirp::Error.
        def add_user_to_organization(req, env)
          unless id_argument(req.user_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          unless id_argument(req.org_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "org_id")
          end

          user = User.find_by(id: req.user_id)
          unless user
            return Twirp::Error.not_found("user does not exist", argument: "user_id")
          end

          if user.organization?
            return Twirp::Error.invalid_argument("user is an organization", argument: "user_id")
          end

          if user.bot?
            return Twirp::Error.invalid_argument("user is a bot", argument: "user_id")
          end

          organization = Organization.find_by(id: req.org_id)
          unless organization
            return Twirp::Error.not_found("organization does not exist", argument: "org_id")
          end

          unless organization.active?
            return Twirp::Error.not_found("organization deleted")
          end

          unless organization.business_or_org_has_seats_for?(user: user)
            return Twirp::Error.not_found("organization does not have a seat for the user")
          end

          if user.blocked_by? organization
            return Twirp::Error.not_found("user is blocked by the organization")
          end

          if organization.enterprise_managed_user_enabled? && emu_mismatch?(organization, user)
            return Twirp::Error.not_found("organization and user are not in the same enterprise")
          end

          organization.add_member(user)

          { success: true }
        end

        private

        def emu_mismatch?(org, user)
          return false unless org.enterprise_managed_user_enabled? || user.is_enterprise_managed?

          org.business != user.enterprise_managed_business
        end
      end
    end
  end
end
