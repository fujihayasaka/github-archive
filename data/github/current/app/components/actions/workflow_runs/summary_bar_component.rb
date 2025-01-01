# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class SummaryBarComponent < ApplicationComponent
      include AvatarHelper
      include BotHelper
      include StatusHelper

      attr_reader :commit, :current_repository

      ENDASH_HTML = GitHub::HTMLSafeString.make("&ndash;")

      def initialize(
        check_suite:,
        commit:,
        current_repository:,
        execution: nil,
        retry_blankstate: false
      )
        @check_suite = check_suite
        @commit = commit
        @current_repository = current_repository
        @execution = execution
        @retry_blankstate = retry_blankstate
      end

      # Logic stripped from workflow_run_item_timing
      def workflow_run_total_duration
        return ENDASH_HTML if status_entity.conclusion == "startup_failure"

        duration = status_entity.duration
        if duration == 0
          ENDASH_HTML
        else
          if GitHub.flipper[:actions_workflowruns_billing_aware_duration].enabled?(current_repository)
            billing_aware_duration(duration, hide_zero_seconds_remainder: false)
          else
            precise_duration(duration)
          end
        end
      end

      memoize def has_billing_data?
        workflow_run.has_billing_data?
      end

      def workflow_run_total_billing_duration
        precise_duration(workflow_run.billing_duration_in_seconds, hide_zero_seconds_remainder: true)
      end

      def workflow_run_actor
        execution_actor || creator || pusher
      end

      def workflow_run_status_text
        # Users should see both "pending" and "waiting" statuses to be "waiting" to avoid confusion
        status = status_entity.status == "pending" ? "waiting" : status_entity.status
        (status_entity.conclusion || status).humanize
      end

      memoize def workflow_run_trigger_header
        case trigger_type
        when Actions::TriggerTypes::RETRY
          "Re-run triggered"
        when Actions::TriggerTypes::ISSUE, Actions::TriggerTypes::ISSUE_COMMENT
          "Triggered via issue"
        when Actions::TriggerTypes::PULL_REQUEST
          "Triggered via pull request"
        when Actions::TriggerTypes::RELEASE
          "Triggered via release"
        when Actions::TriggerTypes::DEPLOYMENT
          "Triggered via deployment"
        when Actions::TriggerTypes::SCHEDULE
          "Triggered via schedule"
        when Actions::TriggerTypes::WORKFLOW_DISPATCH
          "Manually triggered"
        when Actions::TriggerTypes::PUSH
          "Triggered via push"
        else
          if workflow_run.actor_id == GitHub.pages_github_app&.bot_id
            "Triggered via GitHub Pages"
          elsif workflow_run.event.present?
            "Triggered via #{workflow_run.event.humanize.downcase}"
          else
            "Triggered"
          end
        end
      end

      def trigger_action
        case trigger_type
        when Actions::TriggerTypes::RETRY
        when Actions::TriggerTypes::MERGE_GROUP
        when Actions::TriggerTypes::PUSH
          "pushed"
        when Actions::TriggerTypes::ISSUE_COMMENT
          "commented on"
        else
          workflow_run.action
        end
      end

      def branch_name_relevant?
        workflow_run.branch_name_relevant?
      end

      def commit_id_relevant?
        ![Actions::TriggerTypes::RELEASE, Actions::TriggerTypes::PULL_REQUEST].include? original_trigger_type
      end

      memoize def artifacts_count
        @artifacts_count = @check_suite.artifacts&.count if viewing_current?
        @artifacts_count ||= 0
      end

      # For live updates
      def partial_path
        workflow_run_summary_partial_path(workflow_run_id: workflow_run.id, user_id: current_repository.owner.display_login, repository: current_repository)
      end

      def channels
        [@check_suite.channel, @check_suite.workflow_run.artifacts_channel]
      end

      def original_trigger_type
        Actions::TriggerTypes.call(workflow_run: workflow_run)
      end

      private

      def trigger_type
        Actions::TriggerTypes.call(workflow_run: workflow_run, triggered_by_retry: triggered_by_retry?)
      end

      def execution_actor
        @execution.actor if @execution.present?
      end

      def pusher
        workflow_run.check_suite.pusher
      end

      def creator
        workflow_run.check_suite.creator
      end

      memoize def workflow_run
        @check_suite.workflow_run
      end

      memoize def trigger
        workflow_run.trigger
      end

      # In the retry blankstate, the check_suite has been reset and is the source of truth. The newest execution has not yet been created
      # Otherwise, render the status of the passed in execution
      memoize def status_entity
        (@execution.present? && !@retry_blankstate) ? @execution : workflow_run
      end

      # True when rendering the latest execution or the overall checksuite status
      def viewing_current?
        @execution.nil? || @execution.is_latest_execution? || @retry_blankstate
      end

      def triggered_by_retry?
        @execution.present? && (@retry_blankstate || @execution.attempt > 1)
      end
    end
  end
end
