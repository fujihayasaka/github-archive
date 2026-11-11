# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class AgentInitiatedCodeChangesPerLanguageData
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
      totals_by_language = Hash.new(0)
      language_sums = Hash.new { |h, k| h[k] = { added: 0, deleted: 0 } }

      @usage_report.each do |daily_record|
        (daily_record["totals_by_language_feature"] || []).each do |language_feature_record|
          language = language_feature_record["language"]
          feature = language_feature_record["feature"]

          next if language == "unknown"
          next unless CopilotInsightsUsage::Utilities::valid_initiated_feature?(feature:, initiated_by: "agent")

          added   = language_feature_record["loc_added_sum"].to_i
          deleted = language_feature_record["loc_deleted_sum"].to_i

          language_sums[language][:added]   += added
          language_sums[language][:deleted] += deleted
          totals_by_language[language]      += (added + deleted)
        end
      end

      top_languages = CopilotInsightsUsage::Utilities.top_n(totals_by_language)

      if top_languages.include?(Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS)
        others_added = 0
        others_deleted = 0
        language_sums.each do |lang, sums|
          next if top_languages.include?(lang)
          others_added   += sums[:added]
          others_deleted += sums[:deleted]
        end
        language_sums[Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS][:added]   = others_added
        language_sums[Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS][:deleted] = others_deleted
      end

      top_languages.map.with_index(1) do |language, id|
        totals = language_sums[language]
        {
          id: id.to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_language(language),
          values: {
            "Added": totals[:added],
            "Deleted": totals[:deleted]
          }
        }
      end
    end
  end
end
