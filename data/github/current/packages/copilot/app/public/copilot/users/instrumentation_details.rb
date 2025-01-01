# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module InstrumentationDetails
      extend T::Helpers
      include Copilot::Users::Signatures
      include Copilot::Instrumentation::ModelDetails

      abstract!

      sig { override.params(include_trust_tier: T::Boolean).returns(CopilotUserDetails) }
      def copilot_user_details(include_trust_tier: false)
        {
          copilot_user_settings: copilot_user_settings,
          subscription_plan: copilot_subscription_plan,
          is_trial: copilot_active_subscription_item.present? ? T.must(copilot_active_subscription_item).on_free_trial? : false,
          is_technical_preview_user: is_technical_preview_user?,
          free_access_type: copilot_free_user_type,
          trust_tier: include_trust_tier ? trust_tier : nil,
        }
      end

      # separate flag to control this, we don't want to science this since
      # this now uses the actual evaluated value instead of just reading the db
      sig { override.returns(T::Hash[Symbol, Symbol]) }
      def copilot_user_settings
        if user_object.feature_flag_enabled?(:copilot_policy_instrumentation_refactor, default: false)
          copilot_user_settings_candidate
        else
          copilot_user_settings_control
        end
      end

      sig { returns(T::Hash[Symbol, Symbol]) }
      def copilot_user_settings_control
        {
          cli_setting: copilot_cli_setting,
          desktop_setting: copilot_desktop_setting,
          editor_preview_features_setting: copilot_editor_preview_features_setting,
          agent_mode_setting: copilot_agent_mode_setting,
          copilot_extensions_setting: copilot_extensions_policy_setting,
          custom_models_setting: copilot_custom_models_setting,
          editor_chat_setting: copilot_editor_chat_setting,
          automatic_code_review_setting: copilot_automatic_code_review_setting,
          github_chat_setting: copilot_github_chat_setting,
          mobile_chat_setting: copilot_mobile_chat_setting,
          pr_summarizations_setting: copilot_pr_summarizations_setting,
          private_docs_setting: copilot_private_docs_setting,
          snippy_setting: copilot_snippy_setting,
          telemetry_configuration: copilot_telemetry_configuration,
          github_chat_bing_access_setting: copilot_github_chat_bing_access_setting,
          overages_setting: copilot_overages_setting,
          swe_agent_setting: copilot_swe_agent_setting,
          mcp_setting: copilot_mcp_setting,
          spark_setting: copilot_spark_setting,
          insights_setting: copilot_insights_setting,
        }.merge(model_settings)
      end

      sig { returns(T::Hash[Symbol, Symbol]) }
      def copilot_user_settings_candidate
        # merge in special cases for policies that don't have a specific class
        # mostly here for backwards compatibility
        Copilot::Policies.instrumentation_hash(T.bind(self, Copilot::User)).merge({
          telemetry_configuration: copilot_telemetry_configuration,
          of_setting: copilot_o_f_setting,
          overages_setting: copilot_overages_setting,
        })
      end

      sig { returns(Symbol) }
      def copilot_insights_setting
        :INSIGHTS_UNCONFIGURED # We don't have this policy at the user level so it should always be unconfigured
      end

      sig { override.returns(Symbol) }
      def copilot_telemetry_configuration
        return :ENABLED if telemetry_enabled?
        :DISABLED
      end

      sig { override.returns(Symbol) }
      def copilot_snippy_setting
        return :SNIPPY_ENABLED if block_public_code_suggestions?
        return :SNIPPY_DISABLED if allow_public_code_suggestions?
        return :SNIPPY_UNCONFIGURED unless public_code_suggestions_configured?

        :SNIPPY_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_github_chat_bing_access_setting
        return :GITHUB_CHAT_BING_ACCESS_ENABLED if bing_github_chat_enabled?
        return :GITHUB_CHAT_BING_ACCESS_DISABLED if bing_github_chat_disabled?

        :GITHUB_CHAT_BING_ACCESS_UNKNOWN
      end

      # a user can only have their chat enabled or disabled.
      # if they are a CFI user, it's always enabled
      # if they are a CFB user, it's based on their org/ent settings
      sig { override.returns(Symbol) }
      def copilot_editor_chat_setting
        return :EDITOR_CHAT_ENABLED if chat_enabled?
        return :EDITOR_CHAT_DISABLED if chat_disabled?

        :EDITOR_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_github_chat_setting
        return :GITHUB_CHAT_UNCONFIGURED unless dotcom_chat_configured?
        return :GITHUB_CHAT_ENABLED if dotcom_chat_enabled?
        return :GITHUB_CHAT_DISABLED if dotcom_chat_disabled?

        :GITHUB_CHAT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_cli_setting
        return :CLI_UNCONFIGURED unless cli_configured?
        return :CLI_ENABLED if cli_enabled?
        return :CLI_DISABLED if cli_disabled?

        :CLI_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_desktop_setting
        return :DESKTOP_UNCONFIGURED unless desktop_configured?
        return :DESKTOP_ENABLED if desktop_enabled?
        return :DESKTOP_DISABLED if desktop_disabled?

        :DESKTOP_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_editor_preview_features_setting
        return :EDITOR_PREVIEW_FEATURES_UNCONFIGURED unless editor_preview_features_configured?
        return :EDITOR_PREVIEW_FEATURES_ENABLED if editor_preview_features_enabled?
        return :EDITOR_PREVIEW_FEATURES_DISABLED if editor_preview_features_disabled?

        :EDITOR_PREVIEW_FEATURES_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_agent_mode_setting
        return :AGENT_MODE_UNCONFIGURED unless agent_mode_configured?
        return :AGENT_MODE_ENABLED if agent_mode_enabled?
        return :AGENT_MODE_DISABLED if agent_mode_disabled?

        :AGENT_MODE_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_automatic_code_review_setting
        return :AUTOMATIC_CODE_REVIEW_UNCONFIGURED unless automatic_code_review_configured?
        return :AUTOMATIC_CODE_REVIEW_ENABLED if automatic_code_review_enabled?
        return :AUTOMATIC_CODE_REVIEW_DISABLED if automatic_code_review_disabled?

        :AUTOMATIC_CODE_REVIEW_UNKNOWN
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
      def copilot_extensions_policy_setting
        return :COPILOT_EXTENSIONS_UNCONFIGURED unless copilot_extensions_configured?
        return :COPILOT_EXTENSIONS_ENABLED if copilot_extensions_enabled?
        return :COPILOT_EXTENSIONS_DISABLED if copilot_extensions_disabled?
        return :COPILOT_EXTENSIONS_NO_POLICY if copilot_extensions_no_policy?

        :COPILOT_EXTENSIONS_UNKNOWN
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
      def copilot_mobile_chat_setting
        return :MOBILE_CHAT_ENABLED if mobile_chat_enabled?
        return :MOBILE_CHAT_DISABLED if mobile_chat_disabled?

        :MOBILE_CHAT_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_mcp_setting
        return :MCP_ENABLED if mcp_enabled?
        return :MCP_DISABLED if mcp_disabled?

        :MCP_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_overages_setting
        return :OVERAGES_UNCONFIGURED unless overages_configured?
        return :OVERAGES_ENABLED if overages_enabled?
        return :OVERAGES_DISABLED if overages_disabled?

        :OVERAGES_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_swe_agent_setting
        return :SWE_AGENT_ENABLED if swe_agent_enabled?
        return :SWE_AGENT_DISABLED if swe_agent_disabled?

        :SWE_AGENT_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_spark_setting
        return :SPARK_ENABLED if spark_enabled?
        return :SPARK_DISABLED if spark_disabled?

        :SPARK_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_subscription_plan
        return :NO_SUBSCRIPTION unless copilot_active_subscription_item.present?
        return :MONTHLY if T.must(copilot_active_subscription_item).monthly?
        return :YEARLY if T.must(copilot_active_subscription_item).yearly?

        :UNKNOWN_PLAN
      end

      sig { override.returns(Symbol) }
      def copilot_free_user_type
        free_user = FreeUser.find_by(user: self)
        return :FREE_USER_NOT_PRESENT unless free_user.present?

        case free_user.type
        when Copilot::FreeUser::GITHUB_STAR
          :GITHUB_STAR
        when Copilot::FreeUser::MS_MVP
          :MS_MVP
        when Copilot::FreeUser::WORKSHOP
          :WORKSHOP
        when Copilot::FreeUser::Y_COMBINATOR
          :Y_COMBINATOR
        when Copilot::FreeUser::ENGAGED_OSS
          :ENGAGED_OSS
        when Copilot::FreeUser::EDUCATIONAL
          :EDUCATIONAL
        when Copilot::FreeUser::FACULTY
          :FACULTY
        when Copilot::FreeUser::COMPLIMENTARY_ACCESS
          :COMPLIMENTARY_ACCESS
        when Copilot::FreeUser::TECHNICAL_PREVIEW_EXTENSION
          :TECHNICAL_PREVIEW_EXTENSION
        when Copilot::FreeUser::HEY_GITHUB
          :HEY_GITHUB
        else
          # we should never hit here?
          :FREE_USER_UNKNOWN
        end
      end

      sig { returns(Symbol) }
      def trust_tier
        tier = TrustTiers::Tier.for_billable_owner(self.user_object).tier

        # If the user is a seat holder, we need to check the trust tier of the billing plan owner(s)
        if self.access_type.to_s.include?("SEAT")
          copilot_seats = Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: self.user_object.id)
          ff_check = self.user_object.feature_flag_enabled_or_raise?(:copilot_bpo_trust_tier_nil_check) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          copilot_seats.each do |seat|
            if ff_check && (seat.nil? || seat.seat_assignment.nil? || seat.seat_assignment.owner.nil?)
              # If the seat assignment or owner is nil, we can't determine trust tier
              GitHub.logger.info(
                "Nil seat assignment for user",
                "code.namespace" => "Copilot::Users::InstrumentationDetails",
                "code.function" => Kernel.__method__,
                "gh.user.id" => self.user_object.id,
                "copilot.access_type" => self.access_type,
              )
              next
            end
            current_trust_tier = TrustTiers::Tier.for_billable_owner(seat.seat_assignment.owner).tier
            tier = current_trust_tier if current_trust_tier < tier
          end
        end

        return :TRUST_TIER_UNTRUSTED if tier == TrustTiers::Tier::UNTRUSTED
        return :TRUST_TIER_NEUTRAL if tier == TrustTiers::Tier::NEUTRAL
        return :TRUST_TIER_TRUSTED if tier == TrustTiers::Tier::TRUSTED

        :TRUST_TIER_UNKNOWN
      end
    end
  end
end
