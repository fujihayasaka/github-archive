# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class LinesOfCodePerLanguageData
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
      # Calculate combined LOC totals to pick the top languages
      totals_by_language = Hash.new(0)
      @usage_report.each do |daily_record|
        daily_record["totals_by_language_feature"]&.each do |entry|
          language = entry["language"]
          next if language == "unknown"

          totals_by_language[language] += (
            entry["loc_suggested_to_add_sum"].to_i +
            entry["loc_suggested_to_delete_sum"].to_i +
            entry["loc_added_sum"].to_i +
            entry["loc_deleted_sum"].to_i
          )
        end
      end

      top_languages = CopilotInsightsUsage::Utilities.top_n(totals_by_language)

      # Aggregate LOC metrics for the selected languages, grouping any non-top languages into OTHERS
      language_loc_totals = Hash.new { |h, k| h[k] = { suggested_additions: 0, accepted_additions: 0, suggested_deletions: 0, accepted_deletions: 0 } }

      @usage_report.each do |daily_record|
        daily_record["totals_by_language_feature"]&.each do |entry|
          language = entry["language"]
          next if language == "unknown"

          language = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless top_languages.include?(language)

          language_loc_totals[language][:suggested_additions] += entry["loc_suggested_to_add_sum"].to_i
          language_loc_totals[language][:accepted_additions] += entry["loc_added_sum"].to_i
          language_loc_totals[language][:suggested_deletions] += entry["loc_suggested_to_delete_sum"].to_i
          language_loc_totals[language][:accepted_deletions] += entry["loc_deleted_sum"].to_i
        end
      end

      top_languages.map.with_index(1) do |language, id|
        totals = language_loc_totals[language] || { suggested_additions: 0, accepted_additions: 0, suggested_deletions: 0, accepted_deletions: 0 }

        {
          id: id.to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_language(language),
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
