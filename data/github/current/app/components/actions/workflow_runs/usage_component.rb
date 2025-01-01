# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class UsageComponent < ApplicationComponent
      include StatusHelper
      include ActionsHelper

      attr_reader :repository, :workflow_run

      def initialize(repository:, workflow_run:)
        @repository = repository
        @workflow_run = workflow_run
      end

      memoize def workflow_check_runs
        workflow_run.action_check_runs
      end

      def check_runs_grouped_by_name
        workflow_check_runs.group_by { |check_run| check_run.name }
      end

      memoize def check_run_id_to_line_item_map
        workflow_run.billing_usage_line_items.group_by do
          |line_item| line_item.check_run_id
        end
      end
    end
  end
end
