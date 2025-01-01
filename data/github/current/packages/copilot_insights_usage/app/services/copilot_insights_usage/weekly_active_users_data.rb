# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class WeeklyActiveUsersData
    include GitHub::Memoizer

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::LineChartPayload) }
    def payload
      {
        startDate: data.first&.dig(:startDate),
        endDate: data.last&.dig(:endDate),
        data:,
      }
    end

    private

    sig { returns(T::Array[CopilotInsightsUsage::Types::LineChartDataPoint]) }
    memoize def data
      @usage_report.map.with_index(1) do |day_record, id|
        current_date = day_record.dig("day").to_date
        {
          id: id.to_s,
          label: current_date.strftime("%B %d"),
          startDate: current_date,
          endDate: current_date,
          value: day_record.dig("weekly_active_users") || 0,
        }
      end
    end
  end
end
