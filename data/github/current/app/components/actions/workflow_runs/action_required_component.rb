# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class ActionRequiredComponent < ApplicationComponent

      def initialize(check_suite:, current_repository:)
        @check_suite = check_suite
        @workflow_run = check_suite.workflow_run
        @current_repository = current_repository
      end

      def render?
        return false unless @check_suite.action_required?

        return true if @current_repository.feature_enabled?(:actions_required_component_support_all_events)

        pull_request_trigger.present?
      end

      memoize def pull_request_trigger
        @pull_request_trigger = @workflow_run.trigger if @workflow_run.trigger.is_a?(PullRequest)
      end

      def show_approve_button?
        @current_repository.writable_by?(current_user)
      end

      def approve_and_run_path
        workflow_run_rerequest_check_suite_path(
          repository: @current_repository,
          user_id: @current_repository.owner.display_login,
          workflow_run_id: @workflow_run.id,
        )
      end

      def partial_path
        workflow_run_action_required_partial_path(
          repository: @current_repository,
          user_id: @current_repository.owner.display_login,
          workflow_run_id: @workflow_run.id,
        )
      end
    end
  end
end
