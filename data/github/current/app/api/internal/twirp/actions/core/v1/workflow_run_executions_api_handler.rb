# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::WorkflowRunExecutionsAPIService
      class WorkflowRunExecutionsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"]
        handles_service MonolithTwirp::Actions::Core::V1::WorkflowRunExecutionsAPIService

        # Public: Implementation of the GetWorkflowRunExecution Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetWorkflowRunExecutionRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetWorkflowRunExecutionResponse, or a Twirp::Error.
        def get_workflow_run_execution(req, env)
          GetWorkflowRunExecution.call(req, env)
        end
      end
    end
  end
end
