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

      # Try to find the proper display name for most languages from Linguist, otherwise return the original value
      Linguist::Language.find_by_name(language)&.name ||
        language
    end

    sig { params(model: String).returns(String) }
    def self.display_label_for_model(model)
      display_label = case model
      when Copilot::Metrics::UsageReport::EnterpriseDaily::OTHERS then "Other models"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Default.serialize then "Default"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Unknown.serialize then "Unknown"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt50.serialize then "GPT 5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt5Mini.serialize then "GPT-5 mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt5Nano.serialize then "GPT-5 nano"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt45.serialize then "GPT-4.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt41.serialize then "GPT-4.1"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt40.serialize then "GPT 4"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt4o.serialize then "GPT-4o"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt4oMini.serialize then "GPT-4o mini"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gpt35.serialize then "GPT 3.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude40Opus.serialize then "Claude Opus 4"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude40Sonnet.serialize then "Claude Sonnet 4"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude37Sonnet.serialize then "Claude Sonnet 3.7"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude37SonnetThought.serialize then "Claude Sonnet 3.7 Thinking"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Claude35Sonnet.serialize then "Claude Sonnet 3.5"
      when Copilot::Metrics::UsageReport::EnterpriseDaily::Model::Gemini25Pro.serialize then "Gemini 2.5 Pro"
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
      else model
      end
      display_label
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
  end
end
