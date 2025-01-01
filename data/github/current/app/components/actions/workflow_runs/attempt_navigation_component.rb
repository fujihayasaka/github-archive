# typed: true
# frozen_string_literal: true

# This component is equivalent to the updated `Actions::WorkflowRuns::NewAttemptNavigationComponent`. However, this uses
#   the deprecated SelectMenu instead of Primer ActionMenu. This component is still used for the mobile `...` menu and
#   can be replaced when ActionMenu implements submenus. This is being tracked in the following issue:
#   https://github.com/github/actions-build/issues/345

module Actions
  module WorkflowRuns
    class AttemptNavigationComponent < ApplicationComponent
      def initialize(workflow_run:, current_repository:, execution: nil, retry_blankstate: false, pull_request_number: nil)
        @workflow_run = workflow_run
        @current_repository = current_repository
        @current_execution = execution
        @retry_blankstate = retry_blankstate
        @pull_request_number = pull_request_number
      end

      def render?
        @current_execution && (@workflow_run.has_multiple_attempts || @retry_blankstate)
      end

      def button_text
        return "Latest ##{@workflow_run.latest_workflow_run_execution.attempt + 1}" if @retry_blankstate
        return "Latest ##{@current_execution.attempt}" if @current_execution.is_latest_execution? && !@workflow_run.processing_retry?

        "Attempt ##{@current_execution.attempt}"
      end

      def menu_src_path
        workflow_run_attempts_menu_path(
          user_id: @current_repository.owner,
          repository: @current_repository,
          workflow_run_id: @workflow_run.id,
          current_attempt_number: @current_execution.attempt,
          retry_blankstate: @retry_blankstate,
          pr: @pull_request_number
        )
      end
    end
  end
end
