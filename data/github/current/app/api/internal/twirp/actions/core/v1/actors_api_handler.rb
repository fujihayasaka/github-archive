# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::ActorsAPIService
      class ActorsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::ActorsAPIService
        exempt_from_tenant_context_requirement

        # Public: Implementation of the GetActorsInfo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetActorsInfoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetActorsInfoResponse, or a Twirp::Error.
        def get_actors_info(req, env)
          GetActorsInfo.call(req, env)
        end
      end
    end
  end
end
