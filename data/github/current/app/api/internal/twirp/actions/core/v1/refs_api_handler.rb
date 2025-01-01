# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::RefAPIService
      class RefsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::RefsAPIService

        # Public: Implementation of the IsDependabotAssociated Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::IsDependabotAssociatedRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::IsDependabotAssociatedResponse, or a Twirp::Error.
        def is_dependabot_associated_ref(req, env)
          IsDependabotAssociatedRef.call(req)
        end

        # Public: Implementation of the IsCopilotAssociatedRef Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::IsCopilotAssociatedRefRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::IsCopilotAssociatedRefResponse, or a Twirp::Error.
        def is_copilot_associated_ref(req, env)
          IsCopilotAssociatedRef.call(req)
        end
      end
    end
  end
end
