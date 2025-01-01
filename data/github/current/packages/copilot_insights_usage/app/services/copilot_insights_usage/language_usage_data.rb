# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class LanguageUsageData
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
      language_totals = calculate_language_totals
      total = language_totals.values.sum

      return [] if total.zero?

      result = language_totals.map do |language, count|
        {
          name: Utilities.display_label_for_language(language),
          y: Utilities.calculate_percentage(count, total),
        }
      end

      sorted_results = result.sort_by { |data_point| -data_point[:y] }
      sorted_results
    end

    sig { returns(T::Hash[String, Integer]) }
    def calculate_language_totals
      all_languages = top_languages
      language_totals = Hash.new(0)

      @usage_report.each do |daily_record|
        totals_by_language = daily_record.dig("totals_by_language_feature") || []
        totals_by_language.each do |language_data|
          language = language_data["language"]

          # Skip unknown language
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if language == "unknown"
          end

          language = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless all_languages.include?(language)

          generation_count = language_data["code_generation_activity_count"] || 0
          language_totals[language] += generation_count
        end
      end

      language_totals
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
