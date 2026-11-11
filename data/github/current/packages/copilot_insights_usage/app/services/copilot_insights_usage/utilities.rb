# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class Utilities
    sig { params(count: T.any(Float, Integer), total: T.any(Float, Integer)).returns(T.any(Float, Integer)) }
    def self.calculate_percentage(count, total)
      return 0.0 if total == 0
      (count.to_f / total * 100).round(2)
    end

    sig { params(language: String).returns(String) }
    def self.display_label_for_language(language)
      return "Other languages" if language == Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS

      return "TSX" if language == Copilot::Metrics::UsageReport::EnterpriseDaily::TSX

      # Try to find the proper display name for most languages from Linguist, otherwise return the original value
      Linguist::Language.find_by_name(language)&.name ||
        language
    end

    sig { params(model: String).returns(String) }
    def self.display_label_for_model(model)
      # Try to find the model display name from the registry cache first (for new models)
      cached_model = Copilot::ModelsRegistryCache.find_by(model_key: model)
      return cached_model.name if cached_model.present?

      # Fall back to hardcoded mappings for existing models
      case model
      when Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS then "Other models"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Default.serialize then "Default"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize then "Unknown"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Auto.serialize then "Auto"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt51.serialize then "GPT-5.1"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt51Codex.serialize then "GPT-5.1-Codex"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt51CodexMax.serialize then "GPT-5.1-Codex-Max"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt51CodexMini.serialize then "GPT-5.1-Codex-Mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt50.serialize then "GPT-5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt5Mini.serialize then "GPT-5 mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt5Nano.serialize then "GPT-5 nano"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt5Codex.serialize then "GPT-5-Codex"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt45.serialize then "GPT-4.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt41.serialize then "GPT-4.1"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt40.serialize then "GPT 4"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt4o.serialize then "GPT-4o"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt4oMini.serialize then "GPT-4o mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt35.serialize then "GPT 3.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude45Haiku.serialize then "Claude Haiku 4.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude45Sonnet.serialize then "Claude Sonnet 4.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude45Opus.serialize then "Claude Opus 4.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude41Opus.serialize then "Claude Opus 4.1"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude40Opus.serialize then "Claude Opus 4"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude40Sonnet.serialize then "Claude Sonnet 4"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude37Sonnet.serialize then "Claude Sonnet 3.7"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude37SonnetThought.serialize then "Claude Sonnet 3.7 Thinking"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude35Sonnet.serialize then "Claude Sonnet 3.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gemini30Pro.serialize then "Gemini 3.0 Pro"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gemini25Pro.serialize then "Gemini 2.5 Pro"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gemini25Flash.serialize then "Gemini 2.5 Flash"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gemini20Pro.serialize then "Gemini 2.0 Pro"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gemini20Flash.serialize then "Gemini 2.0 Flash"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gemini15Pro.serialize then "Gemini 1.5 Pro"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::O4Mini.serialize then "o4-mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::O3.serialize then "o3"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::O3Mini.serialize then "o3-mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::O1.serialize then "o1"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::O1Mini.serialize then "o1-mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::O1Preview.serialize then "o1-preview"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::GrokCodeFast1.serialize then "Grok Code"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Grok40709.serialize then "Grok 4 (0709)"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Grok4.serialize then "Grok 4"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Grok3Mini.serialize then "Grok 3 mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Grok3.serialize then "Grok 3"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::RaptorMini.serialize then "Raptor mini"
      else model
      end
    end

    sig { params(collection: T::Hash[String, Integer], n: Integer).returns(T::Array[String]) }
    def self.top_n(collection, n: 5)
      list = collection.sort_by { |_, count| -count }.first(n).map(&:first)

      # Use the original list for checking the size, this handles exactly n items
      if collection.size > n && !list.include?(Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS)
        list = list.first(n - 1) + [Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS]
      end

      # This may look like we are doing extra work,
      # but it ensures that "others" is always at the end for any lengths (including < n)
      if list.include?(Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS)
        list = list.reject { |name| name == Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS }
        list << Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS
      end

      list
    end

    sig { params(feature: T.nilable(String), initiated_by: String).returns(T::Boolean) }
    def self.valid_initiated_feature?(feature:, initiated_by:)
      return false unless feature
      case initiated_by
      when "user"
        CopilotInsights::Constants::USER_INITIATED_FEATURES.include?(feature) && feature != "chat_panel_unknown_mode"
      when "agent"
        CopilotInsights::Constants::AGENT_INITIATED_FEATURES.include?(feature)
      else
        false
      end
    end

    # Fill gaps in date-based data arrays to ensure continuous time series
    sig do
      type_parameters(:T).params(
        usage_report: T::Array[T::Hash[String, T.untyped]],
        data_array: T::Array[T.type_parameter(:T)],
        block: T.proc.params(date: Date, id: Integer).returns(T.type_parameter(:T))
      ).returns(T::Array[T.type_parameter(:T)])
    end
    def self.fill_gaps(usage_report, data_array, &block)
      return [] if usage_report.empty?

      # Extract valid dates (filter_map removes nils from bad data)
      dates = usage_report.filter_map { |record| record["day"]&.to_date }
      return data_array if dates.empty?

      start_date, end_date = dates.minmax  # Single pass for min/max
      return data_array if start_date == end_date  # Single day

      # Create hash for fast lookups
      existing_data = data_array.index_by { |item| T.cast(item, T::Hash[Symbol, T.untyped])[:startDate] }

      # Build continuous date series: use existing data or call the block to create one for missing dates
      result = []
      index = 1
      (start_date..end_date).each do |current_date|
        existing_item = existing_data[current_date]

        if existing_item
          # Reassign sequential IDs
          item = T.cast(existing_item.dup, T::Hash[Symbol, T.untyped])
          item[:id] = index.to_s  # Ensure chronological ID sequence
          result << T.cast(item, T.type_parameter(:T))
        else
          result << block.call(current_date, index)
        end
        index += 1
      end

      result
    end
  end
end
