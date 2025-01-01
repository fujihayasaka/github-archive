# typed: true
# frozen_string_literal: true

# This component is equivalent to `Actions::WorkflowRuns::AttemptNavigationComponent`. However, this uses the Primer
#   ActionMenu instead of the deprecated SelectMenu. The original component is still used for the mobile `...` menu and
#   can be replaced when ActionMenu implements submenus. This is being tracked in the following issue:
#   https://github.com/github/actions-build/issues/345

module Actions
  module WorkflowRuns
    class NewAttemptNavigationComponent < AttemptNavigationComponent
      def menu_src_path
        workflow_run_new_attempts_menu_path(
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
