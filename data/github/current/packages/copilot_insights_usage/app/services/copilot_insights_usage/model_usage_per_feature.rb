# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class ModelUsagePerFeature
    include GitHub::Memoizer

    FEATURE_MAPPING = T.let(
      {
        "chat_panel_edit_mode" => "Edit",
        "chat_panel_ask_mode" => "Ask",
        "chat_panel_agent_mode" => "Agent",
        "chat_panel_custom_mode" => "Custom",
        "chat_inline" => "Inline",
      },
      T::Hash[String, String]
    )

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = T.let(usage_report, T::Array[T::Hash[String, T.untyped]])
    end

    sig { returns(CopilotInsightsUsage::Types::CategoryColumnChartPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(T::Array[String]) }
    def top_models
      totals_by_model = Hash.new(0)
      @usage_report.each do |daily_record|
        daily_record["totals_by_model_feature"]&.each do |entry|
          model = entry["model"]
          feature = entry["feature"]

          # Skip unknown model and feature
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
            next if feature == Copilot::Metrics::UsageReport::EnterpriseDaily::Feature::ChatPanelUnknownMode.serialize
          end

          totals_by_model[model] += entry["user_initiated_interaction_count"].to_i
        end
      end

      Utilities.top_n(totals_by_model)
    end

    sig { returns(T::Array[CopilotInsightsUsage::Types::CategoryColumnChartDataPoint]) }
    memoize def data
      all_models = top_models

      model_feature_totals = Hash.new { |h, k| h[k] = Hash.new(0) }
      total = 0

      @usage_report.each do |daily_record|
        daily_record["totals_by_model_feature"]&.each do |model_feature|
          model = model_feature["model"]
          feature = model_feature["feature"]

          # Skip unknown model and feature
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
            next if feature == Copilot::Metrics::UsageReport::EnterpriseDaily::Feature::ChatPanelUnknownMode.serialize
          end

          model = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless all_models.include?(model)
          feature = FEATURE_MAPPING[feature]

          count = model_feature["user_initiated_interaction_count"].to_i

          if feature && count > 0
            model_feature_totals[model][feature] += count
            total += count
          end
        end
      end

      all_models.map.with_index(1) do |model, id|
        {
          id: id.to_s,
          label: Utilities.display_label_for_model(model),
          values: Hash[
            FEATURE_MAPPING.values.map do |feature|
              [feature, Utilities.calculate_percentage(model_feature_totals[model][feature], total)]
            end
          ]
        }
      end
    end
  end
end
