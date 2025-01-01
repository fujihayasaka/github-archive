# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class OldAttemptBannerComponent < ApplicationComponent
      def initialize(workflow_run:, current_repository:, execution: nil, retry_blankstate: false)
        @workflow_run = workflow_run
        @current_repository = current_repository
        @execution = execution
        @retry_blankstate = retry_blankstate
      end

      def render?
        return false unless @execution
        return true if !@execution.is_latest_execution?

        if @workflow_run.processing_retry?
          !@retry_blankstate
        else
          false
        end
      end

      def latest_attempt_path
        workflow_run_path(
          user_id: @current_repository.owner_display_login,
          repository: @current_repository,
          workflow_run_id: @workflow_run.id,
        )
      end
    end
  end
end
