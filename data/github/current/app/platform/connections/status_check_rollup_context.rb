# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class StatusCheckRollupContext < Connections::Base

      total_count_field

      field :status_context_count, Integer, null: false, description: "The number of status contexts in this rollup."

      def status_context_count
        @object.items.count { |item| item.is_a?(::Status) }
      end

      field :check_run_count, Integer, null: false, description: "The number of check runs in this rollup."

      def check_run_count
        @object.items.count { |item| item.is_a?(::CombinedStatus::CheckRunAdapter) }
      end

      field :status_context_counts_by_state, [Objects::StatusContextStateCount], null: true, description: "Counts of status contexts by state."

      def status_context_counts_by_state
        counts = @object.items.filter_map { |status| status.state if status.is_a?(::Status) }.tally

        Enums::StatusState.values.map do |_enum_key, enum_value|
          { state: enum_value.value, count: counts[enum_value.value] || 0 }
        end
      end

      field :check_run_counts_by_state, [Objects::CheckRunStateCount], null: true, description: "Counts of check runs by state."

      def check_run_counts_by_state
        counts = @object.items.filter_map do |check_run|
          check_run.state if check_run.is_a?(::CombinedStatus::CheckRunAdapter)
        end.tally

        Enums::CheckRunState.values.map do |_enum_key, enum_value|
          { state: enum_value.value, count: counts[enum_value.value] || 0 }
        end
      end
    end
  end
end
