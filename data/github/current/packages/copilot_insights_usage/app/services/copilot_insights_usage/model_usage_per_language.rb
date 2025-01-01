# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class ModelUsagePerLanguage
    include GitHub::Memoizer

    sig { params(usage_report: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_report:)
      @usage_report = usage_report
    end

    sig { returns(CopilotInsightsUsage::Types::ModelUsagePerLanguagePayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(T::Hash[Symbol, T::Array[String]]) }
    def top_languages_and_models
      totals_by_model = Hash.new(0)
      totals_by_language = Hash.new(0)
      @usage_report.each do |daily_record|
        daily_record["totals_by_language_model"]&.each do |entry|
          language = entry["language"]
          model = entry["model"]

          # Skip unknown model and language
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
            next if language == "unknown"
          end

          totals_by_language[language] += entry["code_generation_activity_count"].to_i
          totals_by_model[model] += entry["code_generation_activity_count"].to_i
        end
      end

      {
        top_languages: Utilities.top_n(totals_by_language),
        top_models: Utilities.top_n(totals_by_model)
      }
    end

    sig { returns(T::Array[CopilotInsightsUsage::Types::ModelUsagePerLanguageDataPoint]) }
    def data
      top_languages, top_models = top_languages_and_models.values_at(:top_languages, :top_models)
      all_languages = T.must(top_languages)
      all_models = T.must(top_models)

      # Group by language and model, aggregating across all days
      language_model_totals = Hash.new { |h, k| h[k] = Hash.new(0) }
      total = 0

      @usage_report.each do |daily_record|
        daily_record["totals_by_language_model"].each do |language_model|
          language = language_model["language"]
          model = language_model["model"]

          # Skip unknown model and language
          unless FeatureFlag.vexi.enabled?(:copilot_insights_usage_filter_unknown_data, default: false)
            next if model == Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize
            next if language == "unknown"
          end

          # Group non-top languages/models as "Others"
          language = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless all_languages.include?(language)
          model = Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS unless all_models.include?(model)

          count = language_model["code_generation_activity_count"].to_i
          language_model_totals[language][model] += count
          total += count
        end
      end

      # Convert to the desired format
      all_languages.map.with_index(1) do |language, id|
        model_counts = language_model_totals[language]

        model_percentages = all_models.map do |model|
          count = model_counts[model] || 0
          [Utilities.display_label_for_model(model), Utilities.calculate_percentage(count, total)]
        end.to_h

        {
          id: id.to_s,
          label: Utilities.display_label_for_language(language),
          values: model_percentages
        }
      end
    end
  end
end
