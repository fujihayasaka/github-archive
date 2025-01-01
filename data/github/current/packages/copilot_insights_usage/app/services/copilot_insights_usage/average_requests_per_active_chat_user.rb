# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class AverageRequestsPerActiveChatUser
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
      # Get the date range from the available data
      available_dates = @usage_report.map { |record| record.dig("day")&.to_date }.compact.sort
      start_date = available_dates.first
      end_date = available_dates.last

      # Return empty array if we don't have valid date range
      return [] if start_date.nil? || end_date.nil?

      # Create a hash of existing data keyed by date for fast lookup
      existing_data = @usage_report.index_by { |record| record.dig("day")&.to_date }

      # Generate data for all days in the range, filling missing days with zero values
      (start_date..end_date).map.with_index(1) do |current_date, id|
        daily_record = existing_data[current_date] || { "day" => current_date, "totals_by_feature" => [], "daily_active_users" => 0 }

        build_data_point(id, current_date, daily_record)
      end
    end

    sig { params(id: Integer, current_date: Date, daily_record: T::Hash[String, T.untyped]).returns(CopilotInsightsUsage::Types::LineChartDataPoint) }
    def build_data_point(id, current_date, daily_record)
      totals_by_feature = daily_record.dig("totals_by_feature") || []
      all_features_total = sum_code_completion_feature(totals_by_feature)
      daily_active_users = daily_record.dig("daily_active_users") || 0

      avg_requests_per_active_chat_user = daily_active_users.zero? ? 0.0 : (all_features_total.to_f / daily_active_users).round(1)

      {
        id: id.to_s,
        label: current_date.strftime("%B %d"),
        startDate: current_date,
        endDate: current_date,
        value: avg_requests_per_active_chat_user
      }
    end

    sig { params(totals_by_feature: T::Array[T::Hash[String, T.untyped]]).returns(Integer) }
    def sum_code_completion_feature(totals_by_feature)
      # Based on the schema we must exclude the code_completion feature
      all_relevant_features = totals_by_feature.reject { |item| item.dig("feature") == "code_completion" }
      all_relevant_features.sum { |item| item.dig("user_initiated_interaction_count") || 0 }
    end
  end
end
