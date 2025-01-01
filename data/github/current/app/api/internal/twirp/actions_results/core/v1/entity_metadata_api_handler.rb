# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      # Handler for the MonolithTwirp::ActionsResults::Core::V1::EntityMetadataAPIService
      class EntityMetadataAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["actions_results"].freeze
        handles_service MonolithTwirp::ActionsResults::Core::V1::EntityMetadataAPIService

        resolve_tenant_context do |req, _env|
          next nil unless req.respond_to?(:repository_id)
          Repositories::Public.resolve_tenant(id: req.repository_id)
        end

        # Public: Implementation of the GetRepositoryOwnership Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::ActionsResults::Core::V1::GetRepositoryOwnershipRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::ActionsResults::Core::V1::GetRepositoryOwnershipResponse, or a Twirp::Error.
        def get_repository_ownership(req, env)
          GetRepositoryOwnership.call(req, env)
        end
      end
    end
  end
end
