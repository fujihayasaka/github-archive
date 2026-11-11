# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class JobConcurrencyBannerComponent < ApplicationComponent
      include ConcurrencyBannerChannels

      def initialize(check_run:, should_update:)
        @check_run = check_run
        @check_suite = check_run.check_suite
        @should_update = should_update
      end

      RESOLVE_LIMIT = 2

      memoize def blocking_resources
        result = GitHub::WorkflowConcurrency.job_blocking_items(
          @check_suite,
          @check_run,
          resolve_limit: RESOLVE_LIMIT
        )
        @blocked_at_level = result[:blocked_at_level]
        @blocking_resources_count = result[:total_count]
        result[:items]
      end

      def blocking_resources_count
        blocking_resources unless defined?(@blocking_resources_count)
        @blocking_resources_count
      end

      def blocked_at_level
        blocking_resources unless defined?(@blocked_at_level)
        @blocked_at_level
      end

      def blocked_subject_text
        blocked_at_level == "workflow" ? "This job's workflow" : "This job"
      end

      def display?
        @check_run.status == StatusCheckConfig::PENDING && blocking_resources.any?
      end

      private

      # JobConcurrencyBannerComponent is only rendered when FF is on,
      # so acquired_suite_channel is always active.
      def concurrency_queue_ff_enabled?
        true
      end
    end
  end
end
