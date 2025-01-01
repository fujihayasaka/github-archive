# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class CodeCompletionsAcceptanceRateData
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
        totals_by_feature = daily_record.dig("totals_by_feature") || []

        code_completion_feature = totals_by_feature.find { |feature| feature["feature"] == "code_completion" }
        generation_count = code_completion_feature&.dig("code_generation_activity_count") || 0
        acceptance_count = code_completion_feature&.dig("code_acceptance_activity_count") || 0
        code_generation_acceptance_rate = generation_count.zero? ? 0.0 : (acceptance_count.to_f / generation_count * 100).round(1)
        {
          id: id.to_s,
          label: current_date.strftime("%B %d"),
          startDate: current_date,
          endDate: current_date,
          value: code_generation_acceptance_rate
        }
      end
    end
  end
end
