# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class AgentInitiatedCodeChangesData
    include GitHub::Memoizer

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::CategoryColumnChartPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(T::Array[CopilotInsightsUsage::Types::CategoryColumnChartDataPoint]) }
    memoize def data
      added_sum = 0
      deleted_sum = 0

      @usage_report.each do |daily_record|
        agent_edit = (daily_record["totals_by_feature"] || []).find { |feature| feature["feature"] == "agent_edit" }
        added_sum += (agent_edit&.dig("loc_added_sum") || 0).to_i
        deleted_sum += (agent_edit&.dig("loc_deleted_sum") || 0).to_i
      end

      [{
        id: "1",
        label: "Agent",
        values: {
          "Added": added_sum,
          "Deleted": deleted_sum,
        }
      }]
    end
  end
end
