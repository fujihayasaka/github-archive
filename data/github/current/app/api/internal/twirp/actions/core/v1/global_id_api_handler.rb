# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::GlobalIdAPIService
      class GlobalIdAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[launch dependabot_api].freeze
        handles_service MonolithTwirp::Actions::Core::V1::GlobalIdAPIService
        exempt_from_tenant_context_requirement

        # Public: Implementation of the GetNextGlobalId Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetNextGlobalIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetNextGlobalIdResponse, or a Twirp::Error.
        def get_next_global_id(req, env)
          GetNextGlobalId.call(req)
        end
      end
    end
  end
end
