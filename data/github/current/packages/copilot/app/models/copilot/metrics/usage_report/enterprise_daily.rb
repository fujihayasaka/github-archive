# typed: strict
# frozen_string_literal: true

module Copilot::Metrics
  module UsageReport::EnterpriseDaily
    OTHERS = T.let("others", String)
    UNKNOWN_LANGUAGE = T.let("unknown", String)
    TSX = T.let(Set["tsx", "typescriptreact"], T::Set[String])
    JSX = T.let(Set["jsx", "javascriptreact"], T::Set[String])

    class Model < T::Enum
      # If you add a new model here, please also update the display_label_for_model method in CopilotInsightsUsage::Utilities
      # Note that models served from the Copilot Model Registry do not need entries here
      enums do
        Default = new("default")
        Unknown = new("unknown")

        # Automatic model selection
        Auto = new("auto")

        # OpenAI GPT
        Gpt55 = new("gpt-5.5")
        Gpt54 = new("gpt-5-4")
        Gpt54Mini = new("gpt-5.4-mini")
        Gpt54Nano = new("gpt-5.4-nano")
        Gpt53Codex = new("gpt-5.3-codex")
        Gpt52Codex = new("gpt-5.2-codex")
        Gpt52 = new("gpt-5.2")
        Gpt51 = new("gpt-5.1")
        Gpt51Codex = new("gpt-5.1-codex")
        Gpt51CodexMax = new("gpt-5.1-codex-max")
        Gpt51CodexMini = new("gpt-5.1-codex-mini")
        Gpt50 = new("gpt-5.0")
        Gpt5Mini = new("gpt-5-mini")
        Gpt5Nano = new("gpt-5-nano")
        Gpt5Codex = new("gpt-5-codex")
        Gpt45 = new("gpt-4.5")
        Gpt41 = new("gpt-4.1")
        Gpt40 = new("gpt-4.0")
        Gpt4o = new("gpt-4o")
        Gpt4oMini = new("gpt-4o-mini")
        Gpt35 = new("gpt-3.5")

        # Anthropic Claude
        ClaudeFable5 = new("claude-fable-5")
        Claude48Opus = new("claude-opus-4.8")
        Claude47Opus = new("claude-opus-4.7")
        Claude46Sonnet = new("claude-4.6-sonnet")
        Claude46Opus = new("claude-opus-4.6")
        Claude45Opus = new("claude-opus-4.5")
        Claude45Haiku = new("claude-4.5-haiku")
        Claude45Sonnet = new("claude-4.5-sonnet")
        Claude41Opus = new("claude-opus-4.1")
        Claude40Opus = new("claude-opus-4")
        Claude40Sonnet = new("claude-4.0-sonnet")
        Claude37Sonnet = new("claude-3.7-sonnet")
        Claude37SonnetThought = new("claude-3.7-sonnet-thought")
        Claude35Sonnet = new("claude-3.5-sonnet")

        # Google Gemini
        Gemini35Flash = new("gemini-3.5-flash")
        Gemini31Pro = new("gemini-3.1-pro")
        Gemini31FlashLite = new("gemini-3.1-flash-lite")
        Gemini30Pro = new("gemini-3.0-pro")
        Gemini30Flash = new("gemini-3.0-flash")
        Gemini25Pro = new("gemini-2.5-pro")
        Gemini25Flash = new("gemini-2.5-flash")
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

        # Microsoft MAI
        MaiCode1Flash = new("mai-code-1-flash")

        # Microsoft OSWE/Raptor
        RaptorMini = new("raptor-mini")
      end
    end

    class Feature < T::Enum
      enums do
        AgentEdit = new("agent_edit")
        ChatPanelAgentMode = new("chat_panel_agent_mode")
        ChatPanelAskMode = new("chat_panel_ask_mode")
        ChatPanelCustomMode = new("chat_panel_custom_mode")
        ChatPanelEditMode = new("chat_panel_edit_mode")
        ChatPanelPlanMode = new("chat_panel_plan_mode")
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
