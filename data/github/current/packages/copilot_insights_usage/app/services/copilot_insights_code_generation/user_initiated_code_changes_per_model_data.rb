# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class UserInitiatedCodeChangesPerModelData
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

    # Check out the `data` method in `AgentInitiatedCodeChangesPerModelData` if this class needs to be optimised.
    sig { returns(T::Array[CopilotInsightsUsage::Types::CategoryColumnChartDataPoint]) }
    memoize def data
      # Calculate combined LOC totals
      totals_by_model = Hash.new(0)
      @usage_report.each do |daily_record|
        model_features = daily_record["totals_by_model_feature"] || []
        model_features.each do |model_feature_record|
          model = model_feature_record["model"]
          feature = model_feature_record["feature"]

          next if !CopilotInsightsUsage::Utilities::valid_initiated_feature?(feature:, initiated_by: "user")
          next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize

          totals_by_model[model] += (
            model_feature_record["loc_added_sum"].to_i +
            model_feature_record["loc_suggested_to_add_sum"].to_i
          )
        end
      end

      top_models = CopilotInsightsUsage::Utilities.top_n(totals_by_model)
      model_sums = Hash.new { |h, k| h[k] = { added: 0, suggested: 0 } }

      # Aggregate LOC metrics for the selected models, grouping any non-top models into OTHERS
      @usage_report.each do |daily_record|
        model_features = daily_record["totals_by_model_feature"] || []
        model_features.each do |model_feature_record|
          model = model_feature_record["model"]
          feature = model_feature_record["feature"]

          next if !CopilotInsightsUsage::Utilities::valid_initiated_feature?(feature:, initiated_by: "user")
          next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize

          model = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless top_models.include?(model)
          model_sums[model][:added] += model_feature_record["loc_added_sum"].to_i
          model_sums[model][:suggested] += model_feature_record["loc_suggested_to_add_sum"].to_i
        end
      end

      top_models.map.with_index(1) do |model, id|
        totals = model_sums[model]

        {
          id: id.to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_model(model),
          values: {
            "Suggested": totals[:suggested],
            "Added": totals[:added]
          }
        }
      end
    end
  end
end
