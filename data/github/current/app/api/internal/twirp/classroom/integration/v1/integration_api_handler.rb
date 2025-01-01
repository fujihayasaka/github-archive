# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-integration"

module Api::Internal::Twirp::Classroom
  module Integration
    module V1
      # Handler for the MonolithTwirp::Classroom::Integration::V1::IntegrationAPIService
      class IntegrationAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::Integration::V1::IntegrationAPIService
        connected_to_writing_for :install_classroom_app

        ALLOWED_CLASSROOM_INTEGRATION = [:github_classroom, :github_classroom_staging]

        # Public: Implementation of the InstallClassroomApp Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::Integration::V1::InstallClassroomAppRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::Integration::V1::InstallClassroomAppResponse, or a Twirp::Error.
        def install_classroom_app(req, env)
          organization_id = id_argument(req.organization_id)
          unless organization_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          integration_name = req.integration_name
          unless integration_name.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "integration_name")
          end

          organization = Organization.find_by(id: organization_id)
          return Twirp::Error.not_found("organization not found", argument: "organization_id") unless organization

          integration_sym = integration_name.to_sym

          unless ALLOWED_CLASSROOM_INTEGRATION.include?(integration_sym)
            return Twirp::Error.permission_denied("integration does not have permission to access")
          end

          classroom = Apps::Internal.integration(integration_sym)

          installer = organization.admins.first

          organization_installation = classroom.installations_on(organization).first
          if organization_installation.present?
            return { installation_id: organization_installation.id }
          end

          result = classroom.install_on(
            organization,
            repositories: [],
            installer: installer,
            entry_point: :twirp_api_classroom_integration_api_handler
          )
          return Twirp::Error.not_found("could not install app. #{result.error}") unless result.success?

          { installation_id: result.installation.id }
        end
      end
    end
  end
end
