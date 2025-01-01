# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class LanguageUsagePerDayData
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
      totals_by_language.map.with_index(1) do |(current_date, language_totals), id|
        total = language_totals.values.sum

        {
          id: id.to_s,
          label: current_date.strftime("%B %d"),
          startDate: current_date,
          endDate: current_date,
          values: language_totals.map do |language, count|
            {
              name: Utilities.display_label_for_language(language),
              percentage: Utilities.calculate_percentage(count, total)
            }
          end
        }
      end
    end

    sig { returns(T::Hash[Date, T::Hash[String, Integer]]) }
    def totals_by_language
      all_languages = top_languages
      totals_by_language = @usage_report.filter_map do |daily_record|
        next unless daily_record.dig("day") # Skip if "day" is missing

        current_date = daily_record.dig("day").to_date
        total_by_language = Hash.new(0)
        all_languages.map { |language| total_by_language[language] = 0 }  # Initialize counts for top languages
        daily_record["totals_by_language_feature"].each do |language_feature|
          language = language_feature["language"]

          # Skip unknown language
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if language == "unknown"
          end

          language = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless all_languages.include?(language)

          total_by_language[language] += language_feature["code_generation_activity_count"].to_i
        end
        [current_date, total_by_language]
      end.to_h
    end

    sig { returns(T::Array[String]) }
    def top_languages
      totals_by_language = Hash.new(0)
      @usage_report.each do |daily_record|
        daily_record["totals_by_language_feature"]&.each do |entry|
          language = entry["language"]

          # Skip unknown language
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if language == "unknown"
          end

          totals_by_language[language] += entry["code_generation_activity_count"].to_i
        end
      end

      Utilities.top_n(totals_by_language)
    end
  end
end
