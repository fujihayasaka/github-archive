# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class UserInitiatedCodeChangesPerLanguageData
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
      language_sums = Hash.new { |h, k| h[k] = { "Suggested" => 0, "Added" => 0 } }

      # Calculate combined LoC totals by language
      @usage_report.each do |day_record|
        (day_record["totals_by_language_feature"] || []).each do |feature|
          next unless CopilotInsightsUsage::Utilities::valid_initiated_feature?(feature: feature["feature"], initiated_by: "user")
          next if feature["language"] == "unknown"

          lang = feature["language"]
          suggested = feature["loc_suggested_to_add_sum"].to_i
          added = feature["loc_added_sum"].to_i

          language_sums[lang]["Suggested"] += suggested
          language_sums[lang]["Added"] += added
          totals_by_language[lang] += (suggested + added)
        end
      end

      top_languages = CopilotInsightsUsage::Utilities.top_n(totals_by_language)
      top_four_languages = top_languages.take(4) # Exclude 'Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS'
      others = totals_by_language.keys - top_four_languages
      results = []

      top_four_languages.map.with_index(1) do |lang, idx|
        results << {
          id: (idx).to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_language(lang),
          values: language_sums[lang]
        }
      end

      if others.any?
        # Calculate totals of languages not found in the top 4 as 'Other languages'
        other_languages = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS

        others_suggested = others.sum { |lang| language_sums[lang]["Suggested"] }
        others_added = others.sum { |lang| language_sums[lang]["Added"] }

        results << {
          id: (top_four_languages.length + 1).to_s,
          label: CopilotInsightsUsage::Utilities.display_label_for_language(other_languages),
          values: {
            "Suggested" => others_suggested,
            "Added" => others_added
          }
        }
      end
      results
    end
  end
end
