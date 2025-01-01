# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::IntegrationsAPIService
      class IntegrationsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"]
        handles_service MonolithTwirp::Actions::Core::V1::IntegrationsAPIService

        resolve_tenant_context do |req, _env|
          if req.repository_id.blank?
            next Twirp::Error.not_found("repository does not exist", argument: "repository_id")
          end

          Repositories::Public.resolve_tenant(id: req.repository_id)
        end

        # Public: Implementation of the GetIntegrationJobSecrets Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetIntegrationJobSecretsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetIntegrationJobSecretsResponse, or a Twirp::Error.
        def get_integration_job_secrets(req, env)
          GetIntegrationJobSecrets.call(req)
        end
      end
    end
  end
end
