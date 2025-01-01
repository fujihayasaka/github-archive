# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-organizations"

module Api::Internal::Twirp::Classroom
  module Organizations
    module V1
      # Handler for the MonolithTwirp::Classroom::Organizations::V1::OrganizationsAPIService
      class OrganizationsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        connected_to_writing_for :update_organization
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
      end
    end
  end
end
