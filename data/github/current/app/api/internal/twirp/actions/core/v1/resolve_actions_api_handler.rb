# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::ResolveActionsAPIService
      class ResolveActionsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::ResolveActionsAPIService

        # Public: Implementation of the ResolveActions Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::ResolveActionsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::ResolveActionsResponse, or a Twirp::Error.
        def resolve_actions(req, env)
          ResolveActions.call(req, env)
        end
      end
    end
  end
end
