# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class ModelUsagePerDayData
    include GitHub::Memoizer

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::StackedAreaChartPayload) }
    def payload
      {
        startDate: data.first&.dig(:startDate),
        endDate: data.last&.dig(:endDate),
        data:,
      }
    end

    private

    sig { returns(T::Array[CopilotInsightsUsage::Types::StackedAreaChartDataPoint]) }
    memoize def data
      totals_by_model.map.with_index(1) do |(current_date, model_usage), id|
        total = model_usage.values.sum
        values = model_usage.map do |model, count|
          {
            name: Utilities.display_label_for_model(model),
            percentage: Utilities.calculate_percentage(count, total)
          }
        end

        {
          id: id.to_s,
          label: current_date.strftime("%B %d"),
          startDate: current_date,
          endDate: current_date,
          values: values,
        }
      end
    end

    sig { returns(T::Hash[Date, T::Hash[String, T.any(Float, Integer)]]) }
    def totals_by_model
      all_models = top_models
      totals_by_model = @usage_report.filter_map do |daily_record|
        next unless daily_record.dig("day") # Skip if "day" is missing

        current_date = daily_record.dig("day").to_date
        total_by_model = Hash.new(0)
        all_models.map { |model| total_by_model[model] = 0 }  # Initialize counts for top models
        daily_record["totals_by_model_feature"].each do |model_feature|
          model = model_feature["model"]

          # Skip unknown model
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
          end

          model = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless all_models.include?(model)

          # Aggregate user initiated interaction counts by model
          # If the model is not in the top four, categorize it as "Others"
          total_by_model[model] += model_feature["user_initiated_interaction_count"]
        end
        [current_date, total_by_model]
      end.to_h
    end

    sig { returns(T::Array[String]) }
    def top_models
      totals_by_model = Hash.new(0)
      @usage_report.each do |daily_record|
        daily_record["totals_by_model_feature"].each do |model_feature|
          model = model_feature["model"]

          # Skip unknown model
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
          end

          totals_by_model[model] += model_feature["user_initiated_interaction_count"]
        end
      end

      Utilities.top_n(totals_by_model)
    end
  end
end
