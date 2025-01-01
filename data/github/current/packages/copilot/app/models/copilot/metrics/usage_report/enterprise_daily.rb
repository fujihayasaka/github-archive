# typed: strict
# frozen_string_literal: true

module Copilot::Metrics
  module UsageReport::EnterpriseDaily
    OTHERS = T.let("others", String)

    class Model < T::Enum
      # If you add a new model here, please also update the display_label_for_model method in CopilotInsightsUsage::Utilities
      enums do
        Default = new("default")
        Unknown = new("unknown")

        # OpenAI GPT
        Gpt50 = new("gpt-5.0")
        Gpt5Mini = new("gpt-5-mini")
        Gpt5Nano = new("gpt-5-nano")
        Gpt45 = new("gpt-4.5")
        Gpt41 = new("gpt-4.1")
        Gpt40 = new("gpt-4.0")
        Gpt4o = new("gpt-4o")
        Gpt4oMini = new("gpt-4o-mini")
        Gpt35 = new("gpt-3.5")

        # Anthropic Claude
        Claude40Opus = new("claude-opus-4")
        Claude40Sonnet = new("claude-4.0-sonnet")
        Claude37Sonnet = new("claude-3.7-sonnet")
        Claude37SonnetThought = new("claude-3.7-sonnet-thought")
        Claude35Sonnet = new("claude-3.5-sonnet")

        # Google Gemini
        Gemini25Pro = new("gemini-2.5-pro")
        Gemini20Pro = new("gemini-2.0-pro")
        Gemini20Flash = new("gemini-2.0-flash")
        Gemini15Pro = new("gemini-1.5-pro")

        # OpenAI o-series
        O4Mini = new("o4-mini")
        O3 = new("o3")
        O3Mini = new("o3-mini")
        O1 = new("o1")
        O1Mini = new("o1-mini")
        O1Preview = new("o1-preview")

        # xAI Grok
        GrokCodeFast1 = new("grok-code-fast-1")
        Grok40709 = new("grok-4-0709")
        Grok4 = new("grok-4")
        Grok3Mini = new("grok-3-mini")
        Grok3 = new("grok-3")
      end
    end

    class Feature < T::Enum
      enums do
        ChatPanelAgentMode = new("chat_panel_agent_mode")
        ChatPanelAskMode = new("chat_panel_ask_mode")
        ChatPanelCustomMode = new("chat_panel_custom_mode")
        ChatPanelEditMode = new("chat_panel_edit_mode")
        ChatPanelUnknownMode = new("chat_panel_unknown_mode")
        ChatInline = new("chat_inline")
        CodeCompletion = new("code_completion")
      end
    end

    class TotalByIde < T::Struct
      const :ide_name, String
      const :user_initiated_interaction_count, Integer
      const :code_acceptance_activity_count, Integer
      const :code_generation_activity_count, Integer
      const :loc_suggested_to_add_sum, Integer
      const :loc_suggested_to_delete_sum, Integer
      const :loc_added_sum, Integer
      const :loc_deleted_sum, Integer
    end

    class TotalByFeature < T::Struct
      const :feature, String
      const :user_initiated_interaction_count, Integer
      const :code_acceptance_activity_count, Integer
      const :code_generation_activity_count, Integer
      const :loc_suggested_to_add_sum, Integer
      const :loc_suggested_to_delete_sum, Integer
      const :loc_added_sum, Integer
      const :loc_deleted_sum, Integer
    end

    class TotalByLanguageFeature < T::Struct
      const :language, String
      const :feature, String
      const :code_acceptance_activity_count, Integer
      const :code_generation_activity_count, Integer
      const :loc_suggested_to_add_sum, Integer
      const :loc_suggested_to_delete_sum, Integer
      const :loc_added_sum, Integer
      const :loc_deleted_sum, Integer
    end

    class TotalByLanguageModel < T::Struct
      const :language, String
      const :model, String
      const :code_acceptance_activity_count, Integer
      const :code_generation_activity_count, Integer
      const :loc_suggested_to_add_sum, Integer
      const :loc_suggested_to_delete_sum, Integer
      const :loc_added_sum, Integer
      const :loc_deleted_sum, Integer
    end

    class TotalByModelFeature < T::Struct
      const :model, String
      const :feature, String
      const :user_initiated_interaction_count, Integer
      const :code_acceptance_activity_count, Integer
      const :code_generation_activity_count, Integer
      const :loc_suggested_to_add_sum, Integer
      const :loc_suggested_to_delete_sum, Integer
      const :loc_added_sum, Integer
      const :loc_deleted_sum, Integer
    end

    class DayTotal < T::Struct
      const :day, String
      const :user_initiated_interaction_count, Integer
      const :code_acceptance_activity_count, Integer
      const :code_generation_activity_count, Integer
      const :loc_suggested_to_add_sum, Integer
      const :loc_suggested_to_delete_sum, Integer
      const :loc_added_sum, Integer
      const :loc_deleted_sum, Integer
      const :daily_active_users, Integer
      const :weekly_active_users, Integer
      const :monthly_active_users, Integer
      const :monthly_active_agent_users, Integer
      const :monthly_active_chat_users, Integer
      const :totals_by_ide, T::Array[TotalByIde]
      const :totals_by_feature, T::Array[TotalByFeature]
      const :totals_by_language_feature, T::Array[TotalByLanguageFeature]
      const :totals_by_language_model, T::Array[TotalByLanguageModel]
      const :totals_by_model_feature, T::Array[TotalByModelFeature]
    end
  end
end
