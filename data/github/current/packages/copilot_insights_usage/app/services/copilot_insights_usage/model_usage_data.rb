# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class ModelUsageData
    include GitHub::Memoizer

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::DonutChartPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(T::Array[CopilotInsightsUsage::Types::DonutChartDataPoint]) }
    memoize def data
      model_totals = calculate_model_totals
      total = model_totals.values.sum

      return [] if total.zero?

      result = model_totals.map do |model, count|
        {
          name: Utilities.display_label_for_model(model),
          y: Utilities.calculate_percentage(count, total),
        }
      end

      sorted_results = result.sort_by { |data_point| -data_point[:y] }
      sorted_results
    end

    sig { returns(T::Hash[String, Integer]) }
    def calculate_model_totals
      all_models = top_models
      model_totals = Hash.new(0)

      @usage_report.each do |daily_record|
        totals_by_model = daily_record.dig("totals_by_model_feature") || []
        totals_by_model.each do |model_data|
          model = model_data["model"]

          # Skip unknown model
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
          end

          model = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless all_models.include?(model)

          interaction_count = model_data["user_initiated_interaction_count"] || 0
          model_totals[model] += interaction_count
        end
      end

      model_totals
    end

    sig { returns(T::Array[String]) }
    def top_models
      totals_by_model = Hash.new(0)
      @usage_report.each do |daily_record|
        daily_record["totals_by_model_feature"]&.each do |entry|
          model = entry["model"]

          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
          end

          totals_by_model[model] += entry["user_initiated_interaction_count"].to_i
        end
      end

      Utilities.top_n(totals_by_model)
    end
  end
end
