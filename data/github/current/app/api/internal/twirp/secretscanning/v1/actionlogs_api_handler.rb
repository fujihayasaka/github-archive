# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class ActionlogsAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Actionlogs::V1::ActionlogsAPIService)

        allow_access_for :client

        exempt_from_tenant_context_requirement(only: %i[get_workflow_run_by_check_suite])

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Actionlogs::V1::GetWorkflowRunByCheckSuiteRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Actionlogs::V1::GetWorkflowRunByCheckSuiteResponse,
              Twirp::Error
            )
          )
        end
        def get_workflow_run_by_check_suite(req, env)
          if req.check_suite_id == 0
            return Twirp::Error.invalid_argument("must be non-empty", argument: "check_suite_id")
          end

          workflow_run = ::Actions::WorkflowRun.find_by(check_suite_id: req.check_suite_id)

          unless workflow_run
            return Twirp::Error.not_found("workflow run does not exist", argument: "check_suite_id")
          end

          GitHub::Proto::SecretScanning::Actionlogs::V1::GetWorkflowRunByCheckSuiteResponse.new(
            workflow_run_id: workflow_run.id,
            workflow_file_path: workflow_run.workflow_file_path&.b,
            repository_id: workflow_run.repository_id
          )
        end
      end
    end
  end
end
