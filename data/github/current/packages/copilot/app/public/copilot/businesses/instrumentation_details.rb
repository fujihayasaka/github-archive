# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Businesses
    module InstrumentationDetails
      extend T::Helpers
      include Copilot::Businesses::Signatures

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
      def copilot_a_chat_setting
        return :A_CHAT_UNCONFIGURED unless a_chat_configured?
        return :A_CHAT_ENABLED if a_chat_enabled?
        return :A_CHAT_DISABLED if a_chat_disabled?
        return :A_CHAT_NO_POLICY if a_chat_no_policy?

        :A_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_a_f_setting
        return :AF_UNCONFIGURED unless a_f_configured?
        return :AF_ENABLED if a_f_enabled?
        return :AF_DISABLED if a_f_disabled?
        return :AF_NO_POLICY if a_f_no_policy?

        :AF_UNKNOWN
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
      def copilot_g_chat_setting
        return :G_CHAT_UNCONFIGURED unless g_chat_configured?
        return :G_CHAT_ENABLED if g_chat_enabled?
        return :G_CHAT_DISABLED if g_chat_disabled?
        return :G_CHAT_NO_POLICY if g_chat_no_policy?

        :G_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_o1_setting
        return :O1_UNCONFIGURED unless o1_configured?
        return :O1_ENABLED if o1_enabled?
        return :O1_DISABLED if o1_disabled?
        return :O1_NO_POLICY if o1_no_policy?

        :O1_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_o3_setting
        return :O3_UNCONFIGURED unless o3_configured?
        return :O3_ENABLED if o3_enabled?
        return :O3_DISABLED if o3_disabled?
        return :O3_NO_POLICY if o3_no_policy?

        :O3_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_o_ff_setting
        return :OFF_UNCONFIGURED unless o_ff_configured?
        return :OFF_ENABLED if o_ff_enabled?
        return :OFF_DISABLED if o_ff_disabled?
        return :OFF_NO_POLICY if o_ff_no_policy?

        :OFF_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_o_f_setting
        return :OF_UNCONFIGURED unless o_f_configured?
        return :OF_ENABLED if o_f_enabled?
        return :OF_DISABLED if o_f_disabled?
        return :OF_NO_POLICY if o_f_no_policy?

        :OF_UNKNOWN
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

      sig { override.returns(T::Hash[Symbol, Symbol]) }
      def copilot_business_settings
        {
          cli_setting: copilot_cli_setting,
          desktop_setting: copilot_desktop_setting,
          editor_preview_features_setting: copilot_editor_preview_features_setting,
          a_chat_setting: copilot_a_chat_setting,
          af_setting: copilot_a_f_setting,
          g_chat_setting: copilot_g_chat_setting,
          o1_setting: copilot_o1_setting,
          o3_setting: copilot_o3_setting,
          off_setting: copilot_o_ff_setting,
          of_setting: copilot_o_f_setting,
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
        }
      end
    end
  end
end
