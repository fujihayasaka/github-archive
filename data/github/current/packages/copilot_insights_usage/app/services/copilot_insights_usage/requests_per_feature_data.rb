# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class RequestsPerFeatureData
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
        daily_record = existing_data[current_date] || { "day" => current_date, "totals_by_feature" => [] }
        features = daily_record["totals_by_feature"] || []

        build_data_point(id, current_date, features)
      end
    end

    sig { params(id: Integer, current_date: Date, features: T::Array[T::Hash[String, T.untyped]]).returns(CopilotInsightsUsage::Types::ColumnChartDataPoint) }
    def build_data_point(id, current_date, features)
      {
        id: id.to_s,
        label: current_date.strftime("%B %d"),
        startDate: current_date,
        endDate: current_date,
        values: features.each_with_object({
          "Edit" => 0,
          "Ask" => 0,
          "Agent" => 0,
          "Custom" => 0,
          "Inline" => 0,
        }) do |f, acc|
          case f["feature"]
          when Copilot::Metrics::UsageReport::EnterpriseDaily::Feature::ChatPanelEditMode.serialize
            acc["Edit"] = f["user_initiated_interaction_count"].to_i
          when Copilot::Metrics::UsageReport::EnterpriseDaily::Feature::ChatPanelAskMode.serialize
            acc["Ask"] = f["user_initiated_interaction_count"].to_i
          when Copilot::Metrics::UsageReport::EnterpriseDaily::Feature::ChatPanelAgentMode.serialize
            acc["Agent"] = f["user_initiated_interaction_count"].to_i
          when Copilot::Metrics::UsageReport::EnterpriseDaily::Feature::ChatPanelCustomMode.serialize
            acc["Custom"] = f["user_initiated_interaction_count"].to_i
          when Copilot::Metrics::UsageReport::EnterpriseDaily::Feature::ChatInline.serialize
            acc["Inline"] = f["user_initiated_interaction_count"].to_i
          end
          acc
        end
      }
    end
  end
end
