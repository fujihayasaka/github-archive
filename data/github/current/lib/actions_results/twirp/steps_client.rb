# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  module Twirp
    class StepsClient < ActionsResults::Twirp::BaseClient
      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
          change_order: Integer
        ).returns(TwirpResponse)
      end
      def get_workflow_steps(workflow_run_backend_id:, workflow_job_run_backend_id:, change_order:)
        rpc(
          :GetWorkflowSteps,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
          change_order: change_order
        )
      end

      sig do
        params(
          run_jobs_map: T::Hash[String, T::Array[String]]
        ).returns(TwirpResponse)
      end
      def get_multiple_workflow_steps(run_jobs_map:)
        run_jobs_req = run_jobs_map.each_with_object({}) do |(run_id, job_ids), req|
          next if job_ids.nil?
          req[run_id] = ::MonolithTwirp::ActionsResults::Core::V1::GetMultipleWorkflowStepsRequest::JobIDs.new(
            workflow_job_run_backend_ids: job_ids
          )
        end

        rpc(
          :GetMultipleWorkflowSteps,
          jobs_by_run: run_jobs_req
        )
      end

      private

      def twirp_class
        ::MonolithTwirp::ActionsResults::Core::V1::WorkflowStepsAPIClient
      end
    end
  end
end
