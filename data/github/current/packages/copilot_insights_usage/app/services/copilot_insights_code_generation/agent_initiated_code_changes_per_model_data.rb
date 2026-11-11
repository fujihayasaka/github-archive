# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class AgentInitiatedCodeChangesPerModelData
    include GitHub::Memoizer

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::CategoryColumnChartPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(T::Array[CopilotInsightsUsage::Types::CategoryColumnChartDataPoint]) }
    memoize def data
      totals_by_model = Hash.new(0)
      model_sums = Hash.new { |h, k| h[k] = { "Added" => 0, "Deleted" => 0 } }

      # Calculate combined LoC totals by model
      @usage_report.each do |daily_record|
        (daily_record["totals_by_model_feature"] || []).each do |model_feature_record|
          model = model_feature_record["model"]
          feature = model_feature_record["feature"]

          next unless CopilotInsightsUsage::Utilities::valid_initiated_feature?(feature:, initiated_by: "agent")
          next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize

          added = model_feature_record["loc_added_sum"].to_i
          deleted = model_feature_record["loc_deleted_sum"].to_i

          model_sums[model]["Added"] += added
          model_sums[model]["Deleted"] += deleted
          totals_by_model[model] += (added + deleted)
        end
      end

      top_models = CopilotInsightsUsage::Utilities.top_n(totals_by_model)
      top_four_models = top_models.take(4) # Excludes 'Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS'
      others = totals_by_model.keys - top_four_models
      results = []

      top_four_models.map.with_index(1) do |model, idx|
        results << {
          id: (idx).to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_model(model),
          values: model_sums[model]
        }
      end

      if others.any?
        # Calculate totals of models not found in the top 4 as 'Other models'
        other_models = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS

        others_added = others.sum { |model| model_sums[model]["Added"] }
        others_deleted = others.sum { |model| model_sums[model]["Deleted"] }

        results << {
          id: (top_four_models.length + 1).to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_model(other_models),
          values: {
            "Added" => others_added,
            "Deleted" => others_deleted
          }
        }
      end
      results
    end
  end
end
