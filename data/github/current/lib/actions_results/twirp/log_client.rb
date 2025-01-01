# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  module Twirp
    class LogClient < ActionsResults::Twirp::BaseClient

      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
        ).returns(TwirpResponse)
      end
      def get_completed_job_log_url(workflow_run_backend_id:, workflow_job_run_backend_id:)
        rpc(
          :GetCompletedJobLog,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
        )
      end

      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
          step_backend_id: String
        ).returns(TwirpResponse)
      end
      def get_completed_step_log_url(workflow_run_backend_id:, workflow_job_run_backend_id:, step_backend_id:)
        rpc(
          :GetCompletedStepLog,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
          step_backend_id: step_backend_id
        )
      end

      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
          workflow_step_backend_id: String
        ).returns(TwirpResponse)
      end
      def get_step_log_scrollback(workflow_run_backend_id:, workflow_job_run_backend_id:, workflow_step_backend_id:)
        rpc(
          :GetStepLogScrollback,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
          workflow_step_backend_id: workflow_step_backend_id
        )
      end

      sig do
        params(
          workflow_run_backend_id: String,
        ).returns(TwirpResponse)
      end
      def get_completed_run_log_archive(workflow_run_backend_id:)
        rpc(
          :GetCompletedRunLogArchive,
          workflow_run_backend_id: workflow_run_backend_id
        )
      end

      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
        ).returns(TwirpResponse)
      end
      def register_job_run_for_live_logs(workflow_run_backend_id:, workflow_job_run_backend_id:)
        rpc(
          :RegisterJobRunForLiveLogs,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id
        )
      end

      sig do
        params(
          workflow_run_backend_id: String,
        ).returns(TwirpResponse)
      end
      def delete_logs(workflow_run_backend_id:)
        rpc(
          :DeleteLogs,
          workflow_run_backend_id: workflow_run_backend_id
        )
      end

      private

      def twirp_class
        ::MonolithTwirp::ActionsResults::Core::V1::LogAPIClient
      end
    end
  end
end
