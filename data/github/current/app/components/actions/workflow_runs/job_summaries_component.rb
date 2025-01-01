# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class JobSummariesComponent < ApplicationComponent
      attr_reader :check_suite

      # number of jobs to preload summaries
      NUM_PRELOAD_JOBS = 3

      def initialize(current_repository:, current_user:, check_suite:, workflow_job_runs:, execution:, preload_all: false)
        @current_repository = current_repository
        @current_user = current_user
        @check_suite = check_suite
        @workflow_job_runs = workflow_job_runs
        @execution = execution
        @preload_all = preload_all
      end

      def render?
        return false unless logged_in?

        true
      end

      # True when rendering the latest execution or the overall checksuite status
      def viewing_current?
        @execution.nil? || @execution.is_latest_execution?
      end

      # It's expected that the worklow job runs passed to this component have a summary_url
      def filtered_workflow_job_runs
        @workflow_job_runs
      end

      def self.anchor_for(workflow_job_run)
        "summary-#{workflow_job_run.check_run_id}"
      end

      def self.permalink_for(repo, workflow_run, execution, workflow_job_run)
        path_prefix = if execution.present?
          UrlHelpers.workflow_run_attempt_path(user_id: repo.owner_display_login, repository: repo, workflow_run_id: workflow_run.id, attempt: execution.attempt)
        else
          UrlHelpers.workflow_run_path(user_id: repo.owner_display_login, repository: repo, workflow_run_id: workflow_run.id)
        end

        "#{GitHub.url}#{path_prefix}##{self.anchor_for(workflow_job_run)}"
      end
    end
  end
end
