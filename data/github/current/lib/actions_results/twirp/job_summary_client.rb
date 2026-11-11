# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  module Twirp
    class JobSummaryClient < ActionsResults::Twirp::BaseClient
      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String
        ).returns(TwirpResponse)
      end
      def get_job_summary(workflow_run_backend_id:, workflow_job_run_backend_id:)
        rpc(
          :GetJobSummary,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
        )
      end

      private

      def twirp_class
        ::MonolithTwirp::ActionsResults::Core::V1::JobSummaryAPIClient
      end
    end
  end
end
