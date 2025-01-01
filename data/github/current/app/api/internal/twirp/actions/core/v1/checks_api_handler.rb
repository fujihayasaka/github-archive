# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::ChecksAPIService
      class ChecksApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::Actions::Core::V1::ChecksAPIService

        resolve_tenant_context only: %i[
          create_execution
          update_workflow_run
        ] do |req, _env|
          case req
          when MonolithTwirp::Actions::Core::V1::CreateExecutionRequest, MonolithTwirp::Actions::Core::V1::UpdateWorkflowRunRequest
            next nil unless req.repository_id&.global_id.present?

            begin
              repo_id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id&.global_id).last
              next Repositories::Public.resolve_tenant(id: repo_id)
            rescue Platform::Errors::NotFound, ActiveRecord::RecordNotFound => err
              GitHub.logger.info(
                "unable to resolve tenant", {
                  :exception => err,
                  "code.namespace" => self.class.name,
                  "code.function" => __method__,
                  "gh.repo.global_id" => req.repository_id&.global_id
              })

              # We're returning nil for tenant context here so that the API handler can return the appropriate error.
              next nil
            end
          end
        end

        # Public: Implementation of the CreateExecution Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::CreateExecutionRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::CreateExecutionResponse, or a Twirp::Error.
        def create_execution(req, env)
          CreateExecution.call(req)
        end

        # Public: Implementation of the UpdateWorkflowRun Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::UpdateWorkflowRunRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::UpdateWorkflowRunResponse, or a Twirp::Error.
        def update_workflow_run(req, env)
          UpdateWorkflowRun.call(req)
        end

        # Public: Implementation of the UpdateWorkflowRunExecution Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::UpdateWorkflowRunExecutionRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::UpdateWorkflowRunExecutionResponse, or a Twirp::Error.
        def update_workflow_run_execution(req, env)
          UpdateWorkflowRunExecution.call(req)
        end

        # Public: Implementation of the FindPreviousWorkflowRunToReuse Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::FindPreviousWorkflowRunToReuseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::FindPreviousWorkflowRunToReuseResponse, or a Twirp::Error.
        def find_previous_workflow_run_to_reuse(req, env)
          FindPreviousWorkflowRunToReuse.call(req)
        end

        # Public: Implementation of the GetWorkflowRun Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetWorkflowRunRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetWorkflowrunResponse, or a Twirp::Error.
        def get_workflow_run(req, env)
          GetWorkflowRun.call(req)
        end
      end
    end
  end
end
