# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class ChecksApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["actions_results"].freeze
        handles_service MonolithTwirp::ActionsResults::Core::V1::ChecksAPIService
        connected_to_writing_for :create_check_run

        resolve_tenant_context do |req, _env|
          next nil unless req.respond_to?(:repository_id)
          Repositories::Public.resolve_tenant(id: req.repository_id)
        end

        # Public: Implementation of the CreateCheckRun Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::ActionsResults::Core::V1::CreateCheckRunRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::ActionsResults::Core::V1::CreateCheckRunResponse, or a Twirp::Error.
        def create_check_run(req, env)
          CreateCheckRun.call(req, env)
        end

        # Public: Implementation of the CreateCheckRun Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::ActionsResults::Core::V1::GetWorkflowRunExecutionRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::ActionsResults::Core::V1::GetWorkflowRunExecutionResponse, or a Twirp::Error.
        def get_workflow_run_execution(req, env)
          GetWorkflowRunExecution.call(req, env)
        end
      end
    end
  end
end
