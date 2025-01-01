# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Businesses
    module InstrumentationDetails
      extend T::Helpers
      include Copilot::Businesses::Signatures
      include Copilot::Instrumentation::ModelDetails

      abstract!

      sig { override.returns(Symbol) }
      def copilot_snippy_setting
        return :SNIPPY_ENABLED if block_public_code_suggestions?
        return :SNIPPY_DISABLED if allow_public_code_suggestions?
        return :SNIPPY_NO_POLICY if no_public_code_suggestions_policy?

        :SNIPPY_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_editor_chat_setting
        return :EDITOR_CHAT_UNCONFIGURED unless chat_enabled_configured?
        return :EDITOR_CHAT_ENABLED if chat_enabled?
        return :EDITOR_CHAT_DISABLED if chat_disabled?
        return :EDITOR_CHAT_NO_POLICY if no_chat_policy?

        :EDITOR_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_mobile_chat_setting
        return :MOBILE_CHAT_ENABLED if mobile_chat_enabled?
        return :MOBILE_CHAT_DISABLED if mobile_chat_disabled?
        return :MOBILE_CHAT_NO_POLICY if mobile_chat_no_policy?

        :MOBILE_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_github_chat_setting
        return :GITHUB_CHAT_UNCONFIGURED unless dotcom_chat_configured?
        return :GITHUB_CHAT_ENABLED if dotcom_chat_enabled?
        return :GITHUB_CHAT_DISABLED if dotcom_chat_disabled?
        return :GITHUB_CHAT_NO_POLICY if dotcom_chat_no_policy?

        :GITHUB_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_custom_models_setting
        return :CUSTOM_MODELS_UNCONFIGURED unless custom_models_configured?
        return :CUSTOM_MODELS_ENABLED if custom_models_enabled?
        return :CUSTOM_MODELS_DISABLED if custom_models_disabled?
        return :CUSTOM_MODELS_NO_POLICY if custom_models_no_policy?

        :CUSTOM_MODELS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_cli_setting
        return :CLI_UNCONFIGURED unless cli_configured?
        return :CLI_ENABLED if cli_enabled?
        return :CLI_DISABLED if cli_disabled?
        return :CLI_NO_POLICY if cli_no_policy?

        :CLI_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_desktop_setting
        return :DESKTOP_UNCONFIGURED unless desktop_configured?
        return :DESKTOP_ENABLED if desktop_enabled?
        return :DESKTOP_DISABLED if desktop_disabled?
        return :DESKTOP_NO_POLICY if desktop_no_policy?

        :DESKTOP_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_editor_preview_features_setting
        return :EDITOR_PREVIEW_FEATURES_UNCONFIGURED unless editor_preview_features_configured?
        return :EDITOR_PREVIEW_FEATURES_ENABLED if editor_preview_features_enabled?
        return :EDITOR_PREVIEW_FEATURES_DISABLED if editor_preview_features_disabled?
        return :EDITOR_PREVIEW_FEATURES_NO_POLICY if editor_preview_features_no_policy?

        :EDITOR_PREVIEW_FEATURES_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_agent_mode_setting
        return :AGENT_MODE_UNCONFIGURED unless agent_mode_configured?
        return :AGENT_MODE_ENABLED if agent_mode_enabled?
        return :AGENT_MODE_DISABLED if agent_mode_disabled?
        return :AGENT_MODE_NO_POLICY if agent_mode_no_policy?

        :AGENT_MODE_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_automatic_code_review_setting
        return :AUTOMATIC_CODE_REVIEW_UNCONFIGURED unless automatic_code_review_configured?
        return :AUTOMATIC_CODE_REVIEW_ENABLED if automatic_code_review_enabled?
        return :AUTOMATIC_CODE_REVIEW_DISABLED if automatic_code_review_disabled?
        return :AUTOMATIC_CODE_REVIEW_NO_POLICY if automatic_code_review_no_policy?

        :AUTOMATIC_CODE_REVIEW_UNKNOWN
      end

      def copilot_extensions_policy_setting
        return :COPILOT_EXTENSIONS_UNCONFIGURED unless copilot_extensions_configured?
        return :COPILOT_EXTENSIONS_ENABLED if copilot_extensions_enabled?
        return :COPILOT_EXTENSIONS_DISABLED if copilot_extensions_disabled?
        return :COPILOT_EXTENSIONS_NO_POLICY if copilot_extensions_no_policy?

        :COPILOT_EXTENSIONS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_usage_telemetry_api_setting
        return :USAGE_TELEMETRY_API_NO_POLICY if telemetry_aggregation_no_policy?
        return :USAGE_TELEMETRY_API_ENABLED if telemetry_aggregation_enabled?
        return :USAGE_TELEMETRY_API_DISABLED if telemetry_aggregation_disabled?

        :USAGE_TELEMETRY_API_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_private_docs_setting
        return :PRIVATE_DOCS_UNCONFIGURED unless private_docs_configured?
        return :PRIVATE_DOCS_ENABLED if private_docs_enabled?
        return :PRIVATE_DOCS_DISABLED if private_docs_disabled?
        return :PRIVATE_DOCS_NO_POLICY if private_docs_no_policy?

        :PRIVATE_DOCS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_pr_summarizations_setting
        return :PR_SUMMARIZATIONS_UNCONFIGURED unless pr_summarizations_configured?
        return :PR_SUMMARIZATIONS_ENABLED if pr_summarizations_enabled?
        return :PR_SUMMARIZATIONS_DISABLED if pr_summarizations_disabled?
        return :PR_SUMMARIZATIONS_NO_POLICY if pr_summarizations_no_policy?

        :PR_SUMMARIZATIONS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_enabled_setting
        return :COPILOT_ALL_ORGANIZATIONS if copilot_enabled_for_all_organizations?
        return :COPILOT_DISABLED if copilot_disabled?
        return :COPILOT_SELECTED_ORGANIZATIONS if copilot_enabled_for_selected_organizations?
        return :COPILOT_UNCONFIGURED if copilot_unconfigured?

        :COPILOT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_github_chat_bing_access_setting
        return :GITHUB_CHAT_BING_ACCESS_ENABLED if bing_github_chat_enabled?
        return :GITHUB_CHAT_BING_ACCESS_DISABLED if bing_github_chat_disabled?
        return :GITHUB_CHAT_BING_ACCESS_NO_POLICY if bing_github_chat_no_policy?

        :GITHUB_CHAT_BING_ACCESS_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_beta_features_opt_in_setting
        return :COPILOT_BETA_FEATURES_OPT_IN_ENABLED if beta_features_github_chat_enabled?
        return :COPILOT_BETA_FEATURES_OPT_IN_DISABLED if beta_features_github_chat_disabled?
        return :COPILOT_BETA_FEATURES_OPT_IN_NO_POLICY if beta_features_github_chat_no_policy?

        :COPILOT_BETA_FEATURES_OPT_IN_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_mcp_setting
        return :MCP_UNCONFIGURED if mcp_unconfigured?
        return :MCP_ENABLED if mcp_enabled?
        return :MCP_DISABLED if mcp_disabled?
        return :MCP_NO_POLICY if mcp_no_policy?

        :MCP_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_workspace_for_emu_setting
        return :WORKSPACE_FOR_EMU_ENABLED if workspace_for_emu_enabled?

        :WORKSPACE_FOR_EMU_DISABLED
      end

      sig { override.returns(Symbol) }
      def copilot_overages_setting
        return :OVERAGES_UNCONFIGURED unless overages_configured?
        return :OVERAGES_ENABLED if overages_enabled?
        return :OVERAGES_DISABLED if overages_disabled?
        return :OVERAGES_NO_POLICY if overages_no_policy?

        :OVERAGES_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_swe_agent_setting
        return :SWE_AGENT_UNCONFIGURED if swe_agent_unconfigured?
        return :SWE_AGENT_ENABLED if swe_agent_enabled?
        return :SWE_AGENT_DISABLED if swe_agent_disabled?
        return :SWE_AGENT_NO_POLICY if swe_agent_no_policy?

        :SWE_AGENT_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_spark_setting
        return :SPARK_ENABLED if spark_enabled?
        return :SPARK_DISABLED if spark_disabled?
        return :SPARK_NO_POLICY if spark_no_policy?

        :SPARK_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_insights_setting
        return :INSIGHTS_UNCONFIGURED if insights_unconfigured?
        return :INSIGHTS_ENABLED if insights_enabled?
        return :INSIGHTS_DISABLED if insights_disabled?
        return :INSIGHTS_NO_POLICY if insights_no_policy?

        :INSIGHTS_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_ea_user_fallback_policy_setting
        return :EA_USER_FALLBACK_POLICY_ENABLED if ea_user_fallback_policy_enabled?
        return :EA_USER_FALLBACK_POLICY_DISABLED if ea_user_fallback_policy_disabled?

        :EA_USER_FALLBACK_POLICY_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_code_review_setting
        return :CODE_REVIEW_UNCONFIGURED if code_review_unconfigured?
        return :CODE_REVIEW_ENABLED if code_review_enabled?
        return :CODE_REVIEW_DISABLED if code_review_disabled?
        return :CODE_REVIEW_NO_POLICY if code_review_no_policy?

        :CODE_REVIEW_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_code_review_beta_features_setting
        return :CODE_REVIEW_BETA_FEATURES_ENABLED if code_review_beta_features_enabled?
        return :CODE_REVIEW_BETA_FEATURES_DISABLED if code_review_beta_features_disabled?
        return :CODE_REVIEW_BETA_FEATURES_NO_POLICY if code_review_beta_features_no_policy?

        :CODE_REVIEW_BETA_FEATURES_UNKNOWN
      end

      sig { override.returns(T::Hash[Symbol, Symbol]) }
      def copilot_business_settings
        if business_object.feature_flag_enabled?(:copilot_policy_instrumentation_refactor_science, default: false)
          GitHub::Experiment.new "copilot_policy_instrumentation_refactor" do |e|
            e.context(user: business_object.display_login, type: "Business")

            e.use { copilot_business_settings_control }
            e.try { copilot_business_settings_candidate }
          end.run
        else
          copilot_business_settings_control
        end
      end

      sig { returns(T::Hash[Symbol, Symbol]) }
      def copilot_business_settings_control
        {
          cli_setting: copilot_cli_setting,
          desktop_setting: copilot_desktop_setting,
          editor_preview_features_setting: copilot_editor_preview_features_setting,
          agent_mode_setting: copilot_agent_mode_setting,
          automatic_code_review_setting: copilot_automatic_code_review_setting,
          copilot_beta_features_opt_in_setting: copilot_beta_features_opt_in_setting,
          copilot_enabled_setting: copilot_enabled_setting,
          copilot_extensions_setting: copilot_extensions_policy_setting,
          custom_models_setting: copilot_custom_models_setting,
          editor_chat_setting: copilot_editor_chat_setting,
          github_chat_bing_access_setting: copilot_github_chat_bing_access_setting,
          github_chat_setting: copilot_github_chat_setting,
          mobile_chat_setting: copilot_mobile_chat_setting,
          pr_summarizations_setting: copilot_pr_summarizations_setting,
          private_docs_setting: copilot_private_docs_setting,
          snippy_setting: copilot_snippy_setting,
          usage_telemetry_api_setting: copilot_usage_telemetry_api_setting,
          workspace_for_emu_setting: copilot_workspace_for_emu_setting,
          overages_setting: copilot_overages_setting,
          swe_agent_setting: copilot_swe_agent_setting,
          mcp_setting: copilot_mcp_setting,
          ea_user_fallback_policy_setting: copilot_ea_user_fallback_policy_setting,
          spark_setting: copilot_spark_setting,
          insights_setting: copilot_insights_setting,
          code_review_setting: copilot_code_review_setting,
          code_review_beta_features_setting: copilot_code_review_beta_features_setting
        }.merge(model_settings)
      end

      sig { returns(T::Hash[Symbol, Symbol]) }
      def copilot_business_settings_candidate
        # get the settings hash and merge in some special cases for policies
        # that don't use the new system
        Copilot::Policies.instrumentation_hash(T.bind(self, Copilot::Business)).merge({
          copilot_enabled_setting: copilot_enabled_setting,
          overages_setting: copilot_overages_setting,
          of_setting: copilot_o_f_setting
        })
      end
    end
  end
end
