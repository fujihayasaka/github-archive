# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class LinesOfCodePerDayData
    include GitHub::Memoizer

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::ColumnChartPayload) }
    def payload
      {
        startDate: data.first&.dig(:startDate),
        endDate: data.last&.dig(:endDate),
        data:,
      }
    end

    private

    sig { returns(T::Array[CopilotInsightsUsage::Types::ColumnChartDataPoint]) }
    memoize def data
      @usage_report.map.with_index(1) do |daily_record, id|
        current_date = daily_record.dig("day")&.to_date

        {
          id: id.to_s,
          label: current_date.strftime("%B %d"),
          startDate: current_date,
          endDate: current_date,
          values:
            {
              "Suggested": (daily_record.dig("loc_suggested_to_add_sum") || 0) + (daily_record.dig("loc_suggested_to_delete_sum") || 0),
              "Accepted": (daily_record.dig("loc_added_sum") || 0) + (daily_record.dig("loc_deleted_sum") || 0),
            }
        }
      end
    end
  end
end
