# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class DailyTotalLinesOfCodeData
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
              "Added": daily_record.dig("loc_added_sum") || 0,
              "Deleted": daily_record.dig("loc_deleted_sum") || 0
            }
        }
      end
      # TODO: Move packages/copilot_insights_usage/app/services/copilot_insights_usage/utilities.rb to shared folder
      # Then call `Utilities.fill_gaps` for dated data
    end
  end
end
