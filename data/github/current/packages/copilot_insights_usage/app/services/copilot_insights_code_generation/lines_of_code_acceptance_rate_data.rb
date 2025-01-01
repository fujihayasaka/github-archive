# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class LinesOfCodeAcceptanceRateData
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
      @usage_report.map.with_index(1) do |daily_record, id|
        current_date = daily_record.dig("day").to_date

        # Numerator: accepted LOC = loc_added_sum + loc_deleted_sum
        accepted = (daily_record.dig("loc_added_sum") || 0) + (daily_record.dig("loc_deleted_sum") || 0)

        # Denominator: suggested LOC = loc_suggested_to_add_sum + loc_suggested_to_delete_sum
        suggested = (daily_record.dig("loc_suggested_to_add_sum") || 0) + (daily_record.dig("loc_suggested_to_delete_sum") || 0)

        # Acceptance rate: accepted / suggested (expressed as percentage, rounded to 1 decimal place)
        value = suggested.zero? ? 0.0 : (accepted.to_f / suggested * 100).round(1)

        {
          id: id.to_s,
          label: current_date.strftime("%B %d"),
          startDate: current_date,
          endDate: current_date,
          value: value,
        }
      end
    end
  end
end
