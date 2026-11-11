# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class JobRerunDialogsContainerComponent < ApplicationComponent
      # on page load, pass in defer_rendering to avoid slowing down page load
      # defer_rendering defaults to false and should remain false for all live update scenarios
      def initialize(
        current_repository:,
        workflow_run:,
        defer_rendering: false,
        execution: nil
      )
        @current_repository = current_repository
        @workflow_run = workflow_run
        @defer_rendering = defer_rendering
        @execution = execution
      end

      # don't render if we are specifically viewing an old execution
      def render?
        @execution.nil? || @execution.is_latest_execution?
      end

      def render_job_rerun_dialogs?
        check_suite&.rerunnable? && writable? && !check_suite.expired_logs?
      end

      def pull_request_number
        params[:pr]
      end

      memoize def writable?
        @current_repository.writable_by?(current_user)
      end

      memoize def check_suite
        @workflow_run.check_suite
      end

      memoize def check_runs
        @workflow_run.latest_check_runs
      end
    end
  end
end
