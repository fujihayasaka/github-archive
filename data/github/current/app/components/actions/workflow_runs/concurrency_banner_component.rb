# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class ConcurrencyBannerComponent < ApplicationComponent

      def initialize(check_suite:, should_update:)
        @check_suite = check_suite
        @should_update = should_update
      end

      memoize def blocking_resources
        @check_suite&.workflow_run&.get_blocking_resources.sort_by { |r| r[:display_name] }
      end

      def blocked_at_level_verbiage
        blocked_at_workflow_level = blocking_resources.filter { |resource| resource[:blocked_at_level] == "workflow" }
        blocked_at_job_level = blocking_resources.filter { |resource| resource[:blocked_at_level] == "job" }

        return "This workflow is" if blocked_at_workflow_level.any?
        return "A job in this workflow is" if blocked_at_job_level.count == 1
        "Jobs in this workflow are" if blocked_at_job_level.count > 1
      end
    end
  end
end
