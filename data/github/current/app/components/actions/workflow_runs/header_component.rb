# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class HeaderComponent < ApplicationComponent
      include ActionsHelper
      include HydroHelper

      attr_reader :check_suite, :current_repository, :selected_check_run, :execution, :retry_blankstate

      def initialize(
        check_suite:,
        commit:,
        current_repository:,
        selected_check_run: nil,
        selected_tab: nil,
        execution: nil,
        retry_blankstate: false
      )
        @check_suite = check_suite
        @commit = commit
        @current_repository = current_repository
        @selected_check_run = selected_check_run
        @selected_tab = selected_tab
        @execution = execution
        @retry_blankstate = retry_blankstate
      end

      def title
        if FeatureFlag.vexi.enabled_or_raise?(:actions_workflow_title_markdown, current_repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          return helpers.title_markdown(workflow_run.title) if workflow_run.present?
          return helpers.title_markdown(@commit.short_message_text)
        end

        return workflow_run.title if workflow_run.present?
        @commit.short_message_text
      end

      def subtitle
        check_suite.name unless workflow_run.title == check_suite.name
      end

      def run_number
        check_suite&.workflow_run&.run_number
      end

      def status
        status_entity.status
      end

      def conclusion
        status_entity.conclusion
      end

      def favicon_state
        return StatusCheckConfig::PENDING if pending?
        return StatusCheckConfig::FAILURE if status_entity.failure?
        return StatusCheckConfig::FAILURE if status_entity.startup_failure?
        return StatusCheckConfig::SKIPPED if status_entity.skipped?
        return StatusCheckConfig::SUCCESS if status_entity.success?

        StatusCheckConfig::PENDING
      end

      def selected_tab_text
        (@selected_tab || :summary).to_s.humanize.capitalize
      end

      def back_to_pr_number
        params[:pr]
      end

      def back_to_pr_href
        if current_repository && back_to_pr_number
          pull_request = PullRequest.with_number_and_repo(back_to_pr_number, current_repository)
          pull_request_path(pull_request) if pull_request
        end
      end

      def parent_link_href
        return back_to_pr_href if back_to_pr_href

        if filename.present?
          view_workflow_runs_path
        end
      end

      def parent_link_label
        if back_to_pr_href
          "Back to pull request ##{back_to_pr_number}"
        elsif parent_link_href
          check_suite.name
        end
      end

      memoize def writable?
        current_repository.writable_by?(current_user)
      end

      def can_cancel?
        check_suite.cancelable? && writable? && viewing_current? && !@retry_blankstate
      end

      def can_rerun_all_jobs?
        check_suite.rerunnable? && writable? && viewing_current?
      end

      def can_rerun_failed_jobs?
        can_rerun_all_jobs? && workflow_run.has_failed_workflow_job_runs? && !check_suite.expired_logs?
      end

      def workflow_disabled?
        workflow_run.workflow.disabled? && FeatureFlag.vexi.enabled_or_raise?(:disabled_workflow_rerun_jobs, current_repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      end

      # Hide badge builder if we can't find an associated workflow
      def show_badge_builder?
        !GitHub.enterprise? && filename.present?
      end

      def show_delete_all_logs?
        status_entity.completed_log_url.present? && writable? && check_suite.completed?
      end

      def show_view_workflow_file?
        !check_suite.dynamic_workflow?
      end

      def show_view_runs?
        filename.present?
      end

      def show_mobile_actions?
        !logged_in? || can_rerun_all_jobs? || show_view_workflow_file? || show_badge_builder? || can_cancel? || show_delete_all_logs?
      end

      # Live updates
      def header_path
        workflow_run_header_partial_path(
          workflow_run_id: workflow_run.id,
          user_id: current_repository.owner.display_login,
          repository: current_repository,
          selected_check_run_id: selected_check_run&.id,
          pr: back_to_pr_number
        )
      end

      def view_workflow_runs_path
        if check_suite.lab_workflow?
          workflow_runs_list_path(user_id: current_repository.owner.display_login, repository: current_repository, workflow_file_name: filename, lab: true)
        else
          workflow_runs_list_path(user_id: current_repository.owner.display_login, repository: current_repository, workflow_file_name: filename)
        end
      end

      def channel
        check_suite.channel
      end

      def filename
        return check_suite.workflow_filename || "" unless workflow_run.required_workflow_run?

        workflow_run.workflow.filename
      end

      private

      def pending?
        !status_entity.completed?
      end

      memoize def workflow_run
        check_suite.workflow_run
      end

      def has_multiple_attempts?
        @execution && (workflow_run.has_multiple_attempts || @retry_blankstate)
      end

      def delete_confirm_text
        if has_multiple_attempts?
          "Are you sure you want to delete all logs for all attempts of this run?"
        else
          "Are you sure you want to delete all logs for this run?"
        end
      end

      def mobile_nav_content_src
        workflow_run_navigation_partial_path(
          user_id: current_repository.owner,
          repository: current_repository,
          workflow_run_id: workflow_run.id,
          selected_check_run_id: selected_check_run&.id,
          selected_tab: @selected_tab,
          attempt: execution&.attempt)
      end

      # In the retry blankstate, the check_suite has been reset and is the source of truth. The newest execution has not yet been created
      # Otherwise, render the status of the passed in execution
      memoize def status_entity
        (@execution.present? && !@retry_blankstate) ? @execution : check_suite
      end

      # True when rendering the latest execution or the overall checksuite status
      memoize def viewing_current?
        @execution.nil? || (@execution.is_latest_execution? && !workflow_run.processing_retry?) || @retry_blankstate
      end
    end
  end
end
