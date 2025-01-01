# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class LinesOfCodePerModelData
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
      # Calculate combined LOC totals
      totals_by_model = Hash.new(0)
      @usage_report.each do |daily_record|
        daily_record["totals_by_model_feature"].each do |entry|
          model = entry["model"]
          next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize

          totals_by_model[model] += (
            entry["loc_suggested_to_add_sum"].to_i +
            entry["loc_suggested_to_delete_sum"].to_i +
            entry["loc_added_sum"].to_i +
            entry["loc_deleted_sum"].to_i
          )
        end
      end

      top_models = CopilotInsightsUsage::Utilities.top_n(totals_by_model)

      # Aggregate LOC metrics for the selected models, grouping any non-top models into OTHERS
      model_loc_totals = Hash.new { |h, k| h[k] = { suggested_additions: 0, accepted_additions: 0, suggested_deletions: 0, accepted_deletions: 0 } }

      @usage_report.each do |daily_record|
        daily_record["totals_by_model_feature"].each do |entry|
          model = entry["model"]
          next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize

          model = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless top_models.include?(model)

          model_loc_totals[model][:suggested_additions] += entry["loc_suggested_to_add_sum"].to_i
          model_loc_totals[model][:accepted_additions]  += entry["loc_added_sum"].to_i
          model_loc_totals[model][:suggested_deletions] += entry["loc_suggested_to_delete_sum"].to_i
          model_loc_totals[model][:accepted_deletions]  += entry["loc_deleted_sum"].to_i
        end
      end

      top_models.map.with_index(1) do |model, id|
        totals = model_loc_totals[model] || { suggested_additions: 0, accepted_additions: 0, suggested_deletions: 0, accepted_deletions: 0 }

        {
          id: id.to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_model(model),
          values: {
            "Suggested additions": totals[:suggested_additions],
            "Accepted additions": totals[:accepted_additions],
            "Suggested deletions": totals[:suggested_deletions],
            "Accepted deletions": totals[:accepted_deletions],
          }
        }
      end
    end
  end
end
