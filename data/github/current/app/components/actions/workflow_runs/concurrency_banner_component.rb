# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class ConcurrencyBannerComponent < ApplicationComponent
      include ConcurrencyBannerChannels

      def initialize(check_suite:, should_update:)
        @check_suite = check_suite
        @should_update = should_update
      end

      RESOLVE_LIMIT = 2

      memoize def blocking_resources
        if concurrency_queue_ff_enabled?
          result = GitHub::WorkflowConcurrency.workflow_blocking_items(@check_suite, resolve_limit: RESOLVE_LIMIT)
          @blocking_resources_count = result[:total_count]
          result[:items]
        else
          items = @check_suite&.workflow_run&.get_blocking_resources.sort_by { |r| r[:display_name] }
          @blocking_resources_count = items.length
          items
        end
      end

      def blocking_resources_count
        blocking_resources unless defined?(@blocking_resources_count)
        @blocking_resources_count
      end

      def blocked_at_level_verbiage
        blocked_at_workflow_level = blocking_resources.filter { |resource| resource[:blocked_at_level] == "workflow" }
        blocked_at_job_level = blocking_resources.filter { |resource| resource[:blocked_at_level] == "job" }

        return "This workflow is" if blocked_at_workflow_level.any?
        return "A job in this workflow is" if blocked_at_job_level.count == 1
        "Jobs in this workflow are" if blocked_at_job_level.count > 1
      end

      private

      def concurrency_queue_ff_enabled?
        FeatureFlag.vexi.enabled?(:actions_concurrency_queue_display, @check_suite&.repository, default: false)
      end
    end
  end
end
