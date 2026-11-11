# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::WorkflowsAPIService
      class WorkflowsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"]
        handles_service MonolithTwirp::Actions::Core::V1::WorkflowsAPIService

        # Public: Implementation of the FilterActiveWorkflows Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::FilterActiveWorkflowsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::FilterActiveWorkflowsResponse, or a Twirp::Error.
        def filter_active_workflows(req, env)
          FilterActiveWorkflows.call(req, env)
        end
      end
    end
  end
end
