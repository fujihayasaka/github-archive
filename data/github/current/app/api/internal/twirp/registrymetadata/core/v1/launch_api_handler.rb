# typed: true
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::LaunchAPIService
      class LaunchAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::LaunchAPIService

        # The flow operates on ids thus tenant context is not needed
        exempt_from_tenant_context_requirement

        # Public: Implementation of the IntegrationID Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::IntegrationIDRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::IntegrationIDResponse, or a Twirp::Error.
        def integration_i_d(req, env)
          integration_id = GitHub.launch_github_app.id
          if integration_id.nil? || integration_id == 0
            return Twirp::Error.not_found("integration_id not found for launch app")
          end
          {
            integration_id: integration_id
          }
        end
      end
    end
  end
end
