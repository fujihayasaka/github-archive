# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Settings
      extend T::Helpers
      include Copilot::Users::Signatures
      include GitHub::Memoizer

      include Copilot::Users::Settings::Models
      include Copilot::Users::Settings::ModelsRegistry
      include Copilot::Users::Settings::Policies

      abstract!

      include HasConfiguration

      delegate :custom_models, :custom_models_disabled?, :custom_models_enabled?, :custom_models_no_policy?,
               :custom_models_configured?, :custom_models_unconfigured?,
               :cli_no_policy?, :cli_unconfigured?, :private_telemetry, :private_telemetry_unconfigured?, :private_telemetry_configured?,
               :private_telemetry_no_policy?, :private_telemetry_enabled?, :private_telemetry_disabled?, :private_telemetry_disabled!,
               :private_telemetry_enabled!, :private_telemetry_no_policy!,
               :pr_summarizations_no_policy?, :private_docs_no_policy?, :mobile_chat_no_policy?, :copilot_extensions_no_policy?,
               :editor_preview_features_no_policy?, :editor_preview_features_unconfigured?,
               :agent_mode_no_policy?, :agent_mode_unconfigured?,
               :agent_mode_auto_approve_no_policy?, :agent_mode_auto_approve_unconfigured?,
               :automatic_code_review_no_policy?, :automatic_code_review_unconfigured?,
               :afos_no_policy?,
               :g_tf_no_policy?,
               :o1_no_policy?, :o1_unconfigured?,
               :o_ff_no_policy?, :o_ff_unconfigured?,
               :ofct_no_policy?,
               :overages_no_policy?, :overages_unconfigured?,
               :swe_agent_no_policy?, :swe_agent_unconfigured?,
               :billable_customer_id,
               :mcp_no_policy?, :mcp_unconfigured?,
               :spark_no_policy?,
               :spark_force_org, :spark_force_org_disabled!, :spark_force_org_disabled?, :spark_force_org_enabled!, :spark_force_org_enabled?, :spark_force_org_no_policy!, :spark_force_org_no_policy?,
               :insights, :insights_disabled?, :insights_enabled?, :insights_no_policy?, :insights_unconfigured?,
               :code_review_no_policy?, :code_review_unconfigured?,
               :generated_commit_message, :generated_commit_message_no_policy?, :generated_commit_message_unconfigured?,
               :model_policies,
               to: :configuration

      sig { params(copilot_user: Copilot::User, all_policies: Copilot::Users::Policies::CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def policy_enabled?(copilot_user, all_policies, policy)
        # If all policies are empty, we can check the user's configuration
        if all_policies.empty?
          case policy
          when :dotcom_chat
            return configuration.dotcom_chat_enabled?
          when :pr_summarizations
            return configuration.pr_summarizations_enabled?
          when :copilot_for_dotcom
            return configuration.copilot_for_dotcom_enabled?
          when :mobile_chat
            return configuration.mobile_chat_enabled?
          when :copilot_extensions
            return configuration.copilot_extensions_enabled?
          when :chat_enabled
            return has_cfi_access? || has_limited_access?
          when :user_feedback_opt_in
            return user_feedback_opt_in_enabled?
          when :beta_features_github_chat
            return beta_features_github_chat_enabled?
          when :editor_preview_features
            return configuration.editor_preview_features_enabled?
          when :agent_mode
            return !configuration.agent_mode_disabled?
          when :agent_mode_auto_approve
            return !configuration.agent_mode_auto_approve_disabled?
          when :automatic_code_review
            return configuration.automatic_code_review_enabled?
          when :afos
            return false unless Copilot::Users::ModelAccess.model_available?(copilot_user, :afos)
            return configuration.afos_enabled?
          when :g_tf
            return false if has_limited_access?
            return configuration.g_tf_enabled?
          when :gtff
            return false unless user_object.feature_flag_enabled_or_raise?(:copilot_gtff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return configuration.gtff_enabled?
          when :o1
            return false if has_limited_access?
            return configuration.o1_enabled?
          when :o3
            return configuration.o3_enabled?
          when :o_ff
            return false unless Copilot::Users::ModelAccess.model_available?(copilot_user, :o_ff)
            return configuration.o_ff_enabled?
          when :ofct
            return false unless Copilot::Users::ModelAccess.model_available?(copilot_user, :ofct)
            return configuration.ofct_enabled?
          when :obmb
            return false unless Copilot::Users::ModelAccess.model_available?(copilot_user, :obmb)
            return configuration.obmb_enabled?
          when :obmw
            return configuration.obmw_enabled?
          when :aofo
            return false unless Copilot::Users::ModelAccess.model_available?(copilot_user, :aofo)
            return configuration.aofo_enabled?
          when :ofo
            return false unless Copilot::Users::ModelAccess.model_available?(copilot_user, :ofo)
            return true if has_cfi_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return configuration.ofo_enabled?
          when :grok_code
            return false unless Copilot::Users::ModelAccess.model_available?(copilot_user, :grok_code)
            return configuration.grok_code_enabled?
          when :m_ironman
            return false unless user_object.feature_flag_enabled_or_raise?(:copilot_m_ironman) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return configuration.m_ironman_enabled?
          when :m_spiderman
            return configuration.m_spiderman_enabled?
          when :m_thor
            return configuration.m_thor_enabled?
          when :antman
            return false unless user_object.feature_flag_enabled?(:copilot_antman, default: false)
            return configuration.antman_enabled?
          when :hulk
            return false unless user_object.feature_flag_enabled?(:copilot_hulk, default: false)
            return configuration.hulk_enabled?
          when :blackpanther
            return false unless user_object.feature_flag_enabled?(:copilot_blackpanther, default: false)
            return configuration.blackpanther_enabled?
          when :captainamerica
            return false unless user_object.feature_flag_enabled?(:copilot_captainamerica, default: false)
            return configuration.captainamerica_enabled?
          when :wintersoldier
            return false unless user_object.feature_flag_enabled?(:copilot_wintersoldier, default: false)
            return configuration.wintersoldier_enabled?
          when :bing_github_chat
            return bing_github_chat_enabled?
          when :overages
            return false if has_limited_access?
            return configuration.overages_enabled?
          when :swe_agent
            return true if has_swe_agent_access?
            return configuration.swe_agent_enabled?
          when :mcp
            return true if has_mcp_access?
            return configuration.mcp_enabled?
          when :spark
            return true if has_spark_access?
            return configuration.spark_enabled?
          when :insights
            return configuration.insights_enabled?
          when :code_review
            return true if has_code_review_access?
            return configuration.code_review_enabled?
          when :code_review_beta_features
            return code_review_beta_features_enabled?
          when :generated_commit_message
            return generated_commit_message_enabled?
          end
        end

        if policy == :public_code_suggestions || policy == :public_code_suggestions_enabled
          return allow_public_code_suggestions?
        end

        if policy == :generated_commit_message
          return generated_commit_message_enabled?
        end

        case policy
        when :cli, :dotcom_chat, :chat_enabled, :bing_github_chat, :pr_summarizations, :private_docs, :copilot_for_dotcom, :copilot_extensions, :beta_features_github_chat, :editor_preview_features, :automatic_code_review, :g_tf, :gtff, :o1, :o3, :afos, :ofct, :obmb, :obmw, :ofo, :grok_code, :m_ironman, :m_spiderman, :m_thor, :desktop, :mobile_chat, :spark, :code_review, :code_review_beta_features
          copilot_user.enabled_least_restrictive?(all_policies, policy)
        when :o_ff, :aofo
          copilot_user.enabled_least_restrictive_cfe?(all_policies, policy)
        when :agent_mode, :agent_mode_auto_approve
          copilot_user.enabled_least_restrictive_agent_mode?(all_policies, policy)
        when :overages
          copilot_user.enabled_true_least_restrictive?(all_policies, policy)
        when :mcp, :swe_agent
          # MCP/CCA is not supported in GHES
          return false if GitHub.single_business_environment?

          copilot_user.enabled_least_restrictive?(all_policies, policy)
        else
          copilot_user.enabled_most_restrictive?(all_policies, policy)
        end
      end

      sig { params(copilot_user: Copilot::User, all_policies: Copilot::Users::Policies::CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def policy_disabled?(copilot_user, all_policies, policy)

        # If all policies are empty, we can check the user's configuration
        if all_policies.empty?
          case policy
          when :dotcom_chat
            return configuration.dotcom_chat_disabled?
          when :pr_summarizations
            return configuration.pr_summarizations_disabled?
          when :copilot_for_dotcom
            return configuration.copilot_for_dotcom_disabled?
          when :mobile_chat
            return configuration.mobile_chat_disabled?
          when :chat_enabled
            return !has_cfi_access? && !has_limited_access?
          when :editor_preview_features
            return configuration.editor_preview_features_disabled?
          when :agent_mode
            return configuration.agent_mode_disabled?
          when :agent_mode_auto_approve
            return configuration.agent_mode_auto_approve_disabled?
          when :automatic_code_review
            return configuration.automatic_code_review_disabled? && !has_limited_access?
          when :afos
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :afos)
            return configuration.afos_disabled?
          when :g_tf
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :g_tf)
            return configuration.g_tf_disabled?
          when :gtff
            return true unless user_object.feature_flag_enabled_or_raise?(:copilot_gtff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return configuration.gtff_disabled?
          when :o1
            return true if has_limited_access?
            return configuration.o1_disabled?
          when :o3
            return configuration.o3_disabled?
          when :o_ff
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :o_ff)
            return true if has_ci_access? && (!has_pro_plus_access? && !has_max_access?)
            return configuration.o_ff_disabled?
          when :ofct
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :ofct)
            return configuration.ofct_disabled?
          when :obmb
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :obmb)
            return configuration.obmb_disabled?
          when :obmw
            return configuration.obmw_disabled?
          when :aofo
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :aofo)
            return configuration.aofo_disabled?
          when :ofo
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :ofo)
            return false if has_cfi_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return configuration.ofo_disabled?
          when :grok_code
            return true unless Copilot::Users::ModelAccess.model_available?(copilot_user, :grok_code)
            return configuration.grok_code_disabled?
          when :m_ironman
            return true unless user_object.feature_flag_enabled_or_raise?(:copilot_m_ironman) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return configuration.m_ironman_disabled?
          when :m_spiderman
            return configuration.m_spiderman_disabled?
          when :m_thor
            return configuration.m_thor_disabled?
          when :copilot_extensions
            return true unless has_cfi_access?

            return !user_object.feature_flag_enabled_or_raise?(:copilot_extension_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          when :bing_github_chat
            return bing_github_chat_disabled?
          when :overages
            return true if has_limited_access?
            return configuration.overages_disabled?
          when :swe_agent
            return false if has_swe_agent_access?
            return configuration.swe_agent_disabled?
          when :mcp
            return false if has_mcp_access?
            return configuration.mcp_disabled?
          when :spark
            return false if has_spark_access?
            return configuration.spark_disabled?
          when :code_review
            return code_review_disabled?
          when :code_review_beta_features
            return code_review_beta_features_disabled?
          when :generated_commit_message
            return generated_commit_message_disabled?
          when :antman
            return true unless user_object.feature_flag_enabled?(:copilot_antman, default: false)
            return configuration.antman_disabled?
          when :hulk
            return true unless user_object.feature_flag_enabled?(:copilot_hulk, default: false)
            return configuration.hulk_disabled?
          when :blackpanther
            return true unless user_object.feature_flag_enabled?(:copilot_blackpanther, default: false)
            return configuration.blackpanther_disabled?
          when :captainamerica
            return true unless user_object.feature_flag_enabled?(:copilot_captainamerica, default: false)
            return configuration.captainamerica_disabled?
          when :wintersoldier
            return true unless user_object.feature_flag_enabled?(:copilot_wintersoldier, default: false)
            return configuration.wintersoldier_disabled?
          end
        end

        if policy == :public_code_suggestions || policy == :public_code_suggestions_enabled
          return block_public_code_suggestions?
        end

        if policy == :generated_commit_message
          return generated_commit_message_disabled?
        end

        case policy
        when :cli, :dotcom_chat, :chat_enabled, :bing_github_chat, :pr_summarizations, :private_docs, :copilot_for_dotcom, :copilot_extensions, :editor_preview_features_disabled, :automatic_code_review, :g_tf, :gtff, :o1, :o3, :afos, :ofct, :obmb, :obmw, :ofo, :grok_code, :m_ironman, :m_spiderman, :m_thor, :desktop, :mobile_chat, :spark, :code_review
          copilot_user.disabled_least_restrictive?(all_policies, policy)
        when :o_ff, :aofo
          copilot_user.disabled_least_restrictive_cfe?(all_policies, policy)
        when :agent_mode, :agent_mode_auto_approve
          copilot_user.disabled_least_restrictive_agent_mode?(all_policies, policy)
        when :overages
          copilot_user.disabled_true_least_restrictive?(all_policies, policy)
        when :mcp, :swe_agent
          # MCP/CCA is not supported in GHES
          return true if GitHub.single_business_environment?

          copilot_user.disabled_least_restrictive?(all_policies, policy)
        else
          copilot_user.disabled_most_restrictive?(all_policies, policy)
        end
      end

      # Returns true if the user is an exclusive unaffiliated member of any copilot business and that business has ea_user_fallback_policy_enabled?
      sig { override.returns(T::Boolean) }
      memoize def ea_user_fallback_policy_enabled?
        return false unless copilot_businesses.any?

        copilot_businesses.any? do |business|
          business.business_object.exclusive_unaffiliated_member?(user_object) && business.ea_user_fallback_policy_enabled?
        end
      end

      # This is not a user-settable setting but we need this for the signature matching
      sig { override.void }
      def ea_user_fallback_policy_disabled!; end

      sig { override.returns(T::Boolean) }
      memoize def ea_user_fallback_policy_disabled?
        !ea_user_fallback_policy_enabled?
      end

      # This is not a user-settable setting but we need this for the signature matching
      sig { override.void }
      def ea_user_fallback_policy_enabled!; end

      sig { override.returns(String) }
      memoize def ea_user_fallback_policy_setting
        if ea_user_fallback_policy_enabled?
          "enabled"
        else
          "disabled"
        end
      end


      sig { override.returns(T::Boolean) }
      def workspace_enabled?
        return false unless user_object.feature_flag_enabled_or_raise?(:copilot_workspace) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        if user_object.is_enterprise_managed?
          !!copilot_business&.workspace_for_emu_enabled?
        else
          true
        end
      end

      sig { override.returns(T::Boolean) }
      def beta_features_github_chat_disabled?
        !beta_features_github_chat_enabled?
      end

      # Instead of using this method, see if you can use Copilot::Public::User#beta_features_github_chat_enabled?
      sig { override.returns(T::Boolean) }
      memoize def beta_features_github_chat_enabled?
        return false if has_limited_access?
        return true if has_cfi_access?
        return false unless copilot_organizations.any?
        return false if copilot_businesses.any?(&:beta_features_github_chat_disabled?)
        copilot_organizations.any? { |org| org.beta_features_github_chat_enabled? }
      end

      sig { override.returns(T::Boolean) }
      memoize def user_feedback_opt_in_enabled?
        return false unless copilot_organizations.any?
        copilot_organizations.all? { |org| org.user_feedback_opt_in_enabled? }
      end

      sig { override.returns(T::Boolean) }
      memoize def user_feedback_opt_in_disabled?
        !user_feedback_opt_in_enabled?
      end

      sig { returns(T::Boolean) }
      def codequote_enabled?
        # Flag to get around code referencing blocks for certain orgs e.g. GitHub
        return true if user_object.feature_flag_enabled_or_raise?(:copilot_force_code_references) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        # If the user, organization, or business has blocked public code suggestions, they do not need code referencing
        return false if block_public_code_suggestions?

        # Otherwise, if public code suggestions are allowed, code referencing should be enabled.
        allow_public_code_suggestions?
      end

      sig { override.returns(T::Boolean) }
      def chat_enabled?
        if has_cfb_access?
          # ENTERPRISE CHECKS
          # If ANY of the businesses that a user belongs to have disabled chat, the user gets chat_disabled
          return false if copilot_businesses.any?(&:chat_disabled?)
          return true if copilot_businesses.all?(&:chat_enabled?) unless copilot_businesses.empty?

          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:chat_setting)

          # Otherwise, we need to check at the org level
          # ORGANIZATION CHECKS
          # If ANY of the orgs that a user belongs to have enabled chat, the user gets chat_enabled
          return true if copilot_organizations.any?(&:chat_enabled?)
          # Otherwise, the user gets chat_disabled

          return false
        end

        has_cfi_access? #  you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def chat_disabled?
        if has_cfb_access?
          # ENTERPRISE CHECKS
          # If a user belongs to a standalone business and the business has not distinctly enabled chat, the user gets chat_disabled
          # that means it's unconfigured, disabled or set to no_policy
          # If ANY of the businesses that a user belongs to have disabled chat, the user gets chat_disabled
          return true if copilot_businesses.any?(&:chat_disabled?)
          return false if copilot_businesses.all?(&:chat_enabled?)

          # Otherwise, we need to check at the org level
          # ORGANIZATION CHECKS
          # If ANY of the orgs that a user belongs to have enabled chat, the user gets chat_enabled
          return false if copilot_organizations.any?(&:chat_enabled?)
          # Otherwise, the user gets chat_disabled
          return true
        end

        !has_cfi_access? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def mobile_chat
        if mobile_chat_enabled?
          "enabled"
        elsif mobile_chat_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.void }
      def mobile_chat_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(mobile_chat: :enabled)
        end

        GitHub.dogstats.increment(
          "copilot.settings.mobile_chat_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def mobile_chat_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(mobile_chat: :disabled)
        end

        GitHub.dogstats.increment(
          "copilot.settings.mobile_chat_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.returns(T::Boolean) }
      def mobile_chat_enabled?
        # staff only
        return true if user_object.feature_flag_enabled_or_raise?(:copilot_mobile_chat) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if has_limited_access? && !user_object.feature_flag_enabled_or_raise?(:copilot_free_mobile) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return true if has_cfi_access?

        return false if copilot_businesses.any?(&:mobile_chat_disabled?)
        return true if copilot_businesses.all?(&:mobile_chat_enabled?) unless copilot_businesses.empty?

        return true if copilot_organizations.any?(&:mobile_chat_enabled?)
        return false if copilot_organizations.any? && copilot_organizations.all?(&:mobile_chat_disabled?)

        return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:mobile_chat)

        false
      end

      sig { override.returns(T::Boolean) }
      def mobile_chat_disabled?
        return true if has_limited_access? && !user_object.feature_flag_enabled_or_raise?(:copilot_free_mobile) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if has_cfi_access?

        # If any non-business in which the user has a Copilot seat has disabled this
        # feature, it is disabled for the user.
        return true if copilot_businesses.any?(&:mobile_chat_disabled?)
        return false if copilot_businesses.any?(&:mobile_chat_enabled?)

        return false if copilot_organizations.any?(&:mobile_chat_enabled?)
        return true if copilot_organizations.any? && copilot_organizations.all?(&:mobile_chat_disabled?)

        configuration.mobile_chat_disabled?
      end

      sig { override.returns(T::Boolean) }
      def cli_configured?
        return true if copilot_organizations.any?(&:cli_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.cli_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def cli_enabled?
        return true if has_cfi_access?

        return false if copilot_businesses.any?(&:cli_disabled?)
        return true if copilot_businesses.all?(&:cli_enabled?) unless copilot_businesses.empty?

        return true if copilot_organizations.any?(&:cli_enabled?)
        return false if copilot_organizations.any? && copilot_organizations.all?(&:cli_disabled?)

        return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:cli)

        false
      end

      sig { override.returns(T::Boolean) }
      def cli_disabled?
        return false if has_cfi_access?

        # If any non-business in which the user has a Copilot seat has disabled this
        # feature, it is disabled for the user.
        return true if copilot_businesses.any?(&:cli_disabled?)

        return false if copilot_organizations.any?(&:cli_enabled?)
        return true if copilot_organizations.any? && copilot_organizations.all?(&:cli_disabled?)

        configuration.cli_disabled?
      end

      sig { override.returns(String) }
      def cli
        if cli_enabled?
          "enabled"
        elsif cli_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.returns(T::Boolean) }
      def editor_preview_features_configured?
        return true if copilot_organizations.any?(&:editor_preview_features_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.editor_preview_features_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def editor_preview_features_enabled?
        return false unless user_object.feature_flag_enabled_or_raise?(:copilot_next_edit_suggestions) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return true if has_limited_access? || has_cfi_access?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:editor_preview_features_disabled?)
          return true if copilot_businesses.all?(&:editor_preview_features_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:editor_preview_features_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:editor_preview_features)
          return false
        end

        configuration.editor_preview_features_enabled? # you are a cfi user and you get NES
      end

      sig { override.returns(T::Boolean) }
      def editor_preview_features_disabled?
        return true unless user_object.feature_flag_enabled_or_raise?(:copilot_next_edit_suggestions) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if has_limited_access? || has_cfi_access?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:editor_preview_features_disabled?)
          return false if copilot_businesses.all?(&:editor_preview_features_enabled?)
          return false if copilot_organizations.any?(&:editor_preview_features_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:editor_preview_features)
          return true
        end

        configuration.editor_preview_features_disabled? # you are a cfi user and you cannot disable next edit suggestions
      end

      sig { override.returns(String) }
      def editor_preview_features
        if editor_preview_features_enabled?
          "enabled"
        elsif editor_preview_features_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.returns(T::Boolean) }
      def agent_mode_configured?
        return true if copilot_organizations.any?(&:agent_mode_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.agent_mode_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def agent_mode_enabled?
        return true if has_limited_access? || has_cfi_access?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:agent_mode_disabled?)
          return true if copilot_businesses.all?(&:agent_mode_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:agent_mode_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:agent_mode)
          return false if copilot_organizations.any?(&:agent_mode_disabled?)
          return true
        end

        configuration.agent_mode_enabled? # you are a cfi user and you get agent mode
      end

      sig { override.returns(T::Boolean) }
      def agent_mode_disabled?
        return false if has_limited_access? || has_cfi_access?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:agent_mode_disabled?)
          return false if copilot_businesses.all?(&:agent_mode_enabled?)
          return false if copilot_organizations.any?(&:agent_mode_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:agent_mode)
          return true if copilot_organizations.any?(&:agent_mode_disabled?)
          return false
        end

        configuration.editor_preview_features_disabled? # you are a cfi user and you cannot disable agent mode
      end

      sig { override.returns(String) }
      def agent_mode
        if agent_mode_enabled?
          "enabled"
        elsif agent_mode_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.returns(T::Boolean) }
      def agent_mode_auto_approve_configured?
        return true if copilot_organizations.any?(&:agent_mode_auto_approve_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.agent_mode_auto_approve_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def agent_mode_auto_approve_enabled?
        return false if user_object.feature_flag_enabled?(:copilot_agent_mode_auto_approval_disabled, default: false)
        return true if has_limited_access? || has_cfi_access?

        if has_cfb_access?
          return false if copilot_businesses.any?(&:agent_mode_auto_approve_disabled?)
          return true if copilot_businesses.all?(&:agent_mode_auto_approve_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:agent_mode_auto_approve_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:agent_mode_auto_approve)
          return false if copilot_organizations.all?(&:agent_mode_auto_approve_disabled?)
          return true # Enabled by default for cfb users
        end

        configuration.agent_mode_auto_approve_enabled?
      end

      sig { override.returns(T::Boolean) }
      def agent_mode_auto_approve_disabled?
        return true if user_object.feature_flag_enabled?(:copilot_agent_mode_auto_approval_disabled, default: false)
        return false if has_limited_access? || has_cfi_access?

        if has_cfb_access?
          return true if copilot_businesses.any?(&:agent_mode_auto_approve_disabled?)
          return false if copilot_businesses.all?(&:agent_mode_auto_approve_enabled?)
          return false if copilot_organizations.any?(&:agent_mode_auto_approve_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:agent_mode_auto_approve)
          return true if copilot_organizations.all?(&:agent_mode_auto_approve_disabled?)
          return false
        end

        configuration.agent_mode_auto_approve_disabled?
      end

      sig { override.void }
      def agent_mode_auto_approve_no_policy!
        # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_auto_approve_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def agent_mode_auto_approve_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.agent_mode_auto_approve_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_auto_approve_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def agent_mode_auto_approve_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.agent_mode_auto_approve_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_auto_approve_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.returns(String) }
      def agent_mode_auto_approve
        if agent_mode_auto_approve_enabled?
          "enabled"
        elsif agent_mode_auto_approve_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.returns(T::Boolean) }
      def automatic_code_review_configured?
        return true if copilot_organizations.any?(&:automatic_code_review_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.automatic_code_review_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def automatic_code_review_enabled?
        return false if has_limited_access?

        configuration.automatic_code_review_enabled?
      end

      sig { override.returns(T::Boolean) }
      def automatic_code_review_disabled?
        return true if has_limited_access?

        configuration.automatic_code_review_disabled?
      end

      sig { override.returns(String) }
      def automatic_code_review
        if automatic_code_review_enabled?
          "enabled"
        elsif automatic_code_review_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.returns(T::Boolean) }
      def g_tf_unconfigured?
        return false if copilot_organizations.any? { |org| !org.g_tf_unconfigured? }

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.g_tf_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def g_tf_enabled?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:g_tf_disabled?)
          return true if copilot_businesses.all?(&:g_tf_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:g_tf_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:g_tf)
          return false
        end

        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :g_tf)
          return configuration.g_tf_enabled?
        end

        false
      end

      sig { override.returns(T::Boolean) }
      def g_tf_disabled?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:g_tf_disabled?)
          return false if copilot_businesses.all?(&:g_tf_enabled?)
          return false if copilot_organizations.any?(&:g_tf_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:g_tf)
          return true
        end

        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :g_tf)
          return configuration.g_tf_disabled? # you are a cfi user and you cannot disable chat
        end

        true
      end

      sig { override.returns(String) }
      def g_tf
        if g_tf_enabled?
          "enabled"
        elsif g_tf_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.void }
      def g_tf_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_tf_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_tf_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def g_tf_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_tf_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_tf_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def g_tf_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.g_tf_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.returns(T::Boolean) }
      def o1_configured?
        return true if copilot_organizations.any?(&:o1_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.o1_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def o1_enabled?
        return false if has_limited_access?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:o1_disabled?)
          return true if copilot_businesses.all?(&:o1_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:o1_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:o1)
          return false
        end

        if has_cfi_access?
          return true
        end

        configuration.o1_enabled? # you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def o1_disabled?
        return true if has_limited_access?

        if has_cfb_access?
          return true if copilot_businesses.any?(&:o1_disabled?)
          return false if copilot_businesses.all?(&:o1_enabled?)
          return false if copilot_organizations.any?(&:o1_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:o1)
          return true
        end

        if has_cfi_access?
          return false
        end

        configuration.o1_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { override.returns(String) }
      def o1
        if o1_enabled?
          "enabled"
        elsif o1_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.returns(T::Boolean) }
      def o_ff_configured?
        return true if copilot_organizations.any?(&:o_ff_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.o_ff_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def o_ff_enabled?
        least_restrictive_premium_enabled?(
          policy_symbol: :o_ff,
          is_enabled_proc: ->(entity) { entity.o_ff_enabled? },
          is_disabled_proc: ->(entity) { entity.o_ff_disabled? }
        )
      end

      sig { override.returns(T::Boolean) }
      def o_ff_disabled?
        least_restrictive_premium_disabled?(
          policy_symbol: :o_ff,
          is_enabled_proc: ->(entity) { entity.o_ff_enabled? },
          is_disabled_proc: ->(entity) { entity.o_ff_disabled? }
        )
      end

      sig { override.returns(String) }
      def o_ff
        if o_ff_enabled?
          "enabled"
        elsif o_ff_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.returns(T::Boolean) }
      def ofct_unconfigured?
        return false if copilot_organizations.any? { |org| !org.ofct_unconfigured? }

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.ofct_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def ofct_enabled?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:ofct_disabled?)
          return true if copilot_businesses.all?(&:ofct_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:ofct_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:ofct)
          return false
        end

        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :ofct)
          return configuration.ofct_enabled?
        end

        false
      end

      sig { override.returns(T::Boolean) }
      def ofct_disabled?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:ofct_disabled?)
          return false if copilot_businesses.all?(&:ofct_enabled?)
          return false if copilot_organizations.any?(&:ofct_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:ofct)
          return true
        end

        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :ofct)
          return configuration.ofct_disabled? # you are a cfi user and you cannot disable chat
        end

        true
      end

      sig { returns(String) }
      def ofct
        if ofct_enabled?
          "enabled"
        elsif ofct_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.void }
      def ofct_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.ofct_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.ofct_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def ofct_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.ofct_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.ofct_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def ofct_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.ofct_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.returns(T::Boolean) }
      def pr_summarizations_configured?
        return true if copilot_organizations.any?(&:pr_summarizations_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.pr_summarizations_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      memoize def pr_summarizations_enabled?
        if user_object.businesses.count > 1
          user_object.businesses.each do |business|
            return false if Copilot::Business.new(business).pr_summarizations_disabled?
          end
        end

        return true if copilot_organizations.any?(&:pr_summarizations_enabled?)

        return false if copilot_organizations.any? && copilot_organizations.all?(&:pr_summarizations_disabled?)

        # if they have CI then dotcom chat is always enabled
        # otherwise we fall through to their cached settings
        return true if has_ci_access?

        # limited users don't have access to pr summarizations
        return false if has_limited_access?

        configuration.pr_summarizations_enabled?
      end

      sig { override.returns(T::Boolean) }
      def pr_summarizations_disabled?
        return true if copilot_organizations.any?(&:pr_summarizations_disabled?)

        return false if copilot_organizations.any?(&:pr_summarizations_enabled?)

        configuration.pr_summarizations_disabled?
      end

      sig { override.returns(T::Boolean) }
      def pr_summarizations_unconfigured?
        configuration.pr_summarizations_unconfigured?
      end

      sig { override.returns(T::Boolean) }
      def private_docs_configured?
        return true if copilot_organizations.any?(&:private_docs_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.private_docs_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def private_docs_enabled?
        if user_object.businesses.count > 1
          user_object.businesses.each do |business|
            return false if Copilot::Business.new(business).private_docs_disabled?
          end
        end

        return true if copilot_organizations.any?(&:private_docs_enabled?)

        return false if copilot_organizations.any? && copilot_organizations.all?(&:private_docs_disabled?)

        configuration.private_docs_enabled?
      end

      sig { override.returns(T::Boolean) }
      def private_docs_disabled?
        return true if copilot_organizations.any?(&:private_docs_disabled?)

        return false if copilot_organizations.any?(&:private_docs_enabled?)

        configuration.private_docs_disabled?
      end

      sig { override.returns(T::Boolean) }
      def private_docs_unconfigured?
        configuration.private_docs_unconfigured?
      end

      sig { override.returns(T::Boolean) }
      def overages_configured?
        return true if copilot_organizations.any?(&:overages_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.overages_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def overages_enabled?
        return false if has_limited_access?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:overages_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:overages_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:overages)
          return false
        end

        configuration.overages_enabled?
      end

      sig { override.returns(T::Boolean) }
      def overages_disabled?
        return true if has_limited_access?

        if has_cfb_access?
          return false if copilot_businesses.any?(&:overages_enabled?)
          return false if copilot_organizations.any?(&:overages_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:overages)
          return true
        end

        !configuration.overages_enabled?
      end

      sig { override.returns(String) }
      def overages
        if overages_enabled?
          "enabled"
        elsif overages_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end


      sig { override.returns(T::Boolean) }
      def swe_agent_enabled?
        return true if has_swe_agent_access?

        configuration.swe_agent_enabled?
      end

      sig { override.returns(T::Boolean) }
      def swe_agent_disabled?
        return false if has_swe_agent_access?

        configuration.swe_agent_disabled?
      end

      sig { returns(String) }
      def swe_agent
        if swe_agent_enabled?
          "enabled"
        else
          "disabled"
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_swe_agent_access?
        # User has access if they are pro+
        return true if has_pro_plus_access?
        return true if has_max_access?
        return true if has_pro_access? || has_trial_subscription?
        return true if has_free_access?
        return true if limited_tier_has_swe_agent_access?

        if has_cfe_access? || has_cfb_access?
          # If any of the businesses disable the policy, the user gets disabled
          return false if copilot_businesses.any?(&:swe_agent_disabled?)
          # If the user belongs to any businesses and they all enable it, the user gets enabled
          return true if copilot_businesses.all?(&:swe_agent_enabled?) unless copilot_businesses.empty?
          # If any of the orgs enable the policy, the user gets enabled (least restrictive)
          return true if copilot_organizations.any? do |org|
            org.swe_agent_enabled?
          end
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:swe_agent)

          return false
        end

        false
      end

      sig { override.returns(T::Boolean) }
      def mcp_enabled?
        has_mcp_access?
      end

      sig { override.returns(T::Boolean) }
      def mcp_disabled?
        !mcp_enabled?
      end

      sig { returns(String) }
      def mcp
        if mcp_enabled?
          "enabled"
        else
          "disabled"
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_mcp_access?
        # Users on CFI plan get access to MCP
        return true if has_cfi_access?
        return true if has_pro_access? || has_trial_subscription?
        return true if has_free_access?

        if has_cfe_access? || has_cfb_access?
          if user_object.feature_flag_enabled?(:mcp_access_routing_allignment, default: false)
            return Copilot::Policies::Mcp.effective_value(copilot_user_object, copilot_user_object.all_policies) == Copilot::Policies::Mcp.config_values[:enabled]
          end

          # If any of the businesses disable the policy, the user gets disabled
          return false if copilot_businesses.any?(&:mcp_disabled?)
          # If the user belongs to any businesses and they all enable it, the user gets enabled
          return true if copilot_businesses.all?(&:mcp_enabled?) unless copilot_businesses.empty?
          # If any of the orgs enable the policy, the user gets enabled (least restrictive)
          return true if copilot_organizations.any? do |org|
            org.mcp_enabled?
          end

          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:mcp)
          return false
        end

        false
      end

      sig { override.returns(T::Boolean) }
      def spark_enabled?
        return true if has_spark_access?

        configuration.spark_enabled?
      end

      sig { override.returns(T::Boolean) }
      def spark_disabled?
        return false if has_spark_access?

        configuration.spark_disabled?
      end

      sig { returns(String) }
      def spark
        if spark_enabled?
          "enabled"
        else
          "disabled"
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_spark_access?
        if user_object.feature_flag_enabled?(:spark_policy_migration_experiment, default: false)
          Scientist.run "spark_policy_migration_experiment" do |e|
            e.use do
              has_spark_access_control?
            end

            e.try do
              Copilot::Policies::Spark.effective_value(copilot_user_object) == "enabled"
            end
          end
        else
          has_spark_access_control?
        end
      end

      sig { returns(T::Boolean) }
      def has_spark_access_control?
        if has_cfe_access? || has_cfb_access?
          # If any of the businesses/enterprises enables Spark, let them in (least restrictive)
          return true if copilot_businesses.any?(&:spark_enabled?)

          # If any of the orgs enable the Spark, the user gets enabled (least restrictive)
          return true if copilot_enterprise_organizations.any?(&:spark_enabled?)

          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:spark)

          # If no orgs or enterprises have enabled Spark, the user does not get access
          return false
        end

        # User has access if they're on an individual Copilot plan
        has_cfi_access?
      end

      sig { override.returns(T::Boolean) }
      def code_review_enabled?
        return true if has_code_review_access?

        configuration.code_review_enabled?
      end

      sig { override.returns(T::Boolean) }
      def code_review_disabled?
        return false if has_code_review_access?

        # If user doesn't have access, check that businesses and organizations have not disabled the policy
        return true if copilot_businesses.any?(&:code_review_disabled?)
        return true if copilot_organizations.any? && copilot_organizations.all?(&:code_review_disabled?)

        configuration.code_review_disabled?
      end

      sig { override.returns(T::Boolean) }
      def code_review_beta_features_disabled?
        !code_review_beta_features_enabled?
      end

      sig { override.returns(T::Boolean) }
      memoize def code_review_beta_features_enabled?
        return false unless has_code_review_access?
        # User has beta feature access if they are free pro, pro, or pro+
        return true if has_max_access? || has_pro_plus_access? || has_pro_access? || has_free_access?
        return false unless has_cfe_access? || has_cfb_access?
        return false if copilot_businesses.any?(&:code_review_beta_features_disabled?)
        return false unless copilot_organizations.any?
        copilot_organizations.any? { |org| org.code_review_beta_features_enabled? }
      end

      sig { returns(T::Boolean) }
      memoize def has_code_review_access?
        # User has access if they have complimentary access (OSS, educational)
        return true if has_free_access?

        # User has access if they are pro or pro+
        return true if has_max_access? || has_pro_plus_access? || has_pro_access? || has_trial_subscription?

        return false unless has_cfe_access? || has_cfb_access?
        # If any of the businesses disable the policy, the access is disabled
        return false if copilot_businesses.any?(&:code_review_disabled?)

        # If the user is a part of a standalone business, they have access if the business has enabled code review
        if has_copilot_standalone_business?
          return copilot_businesses.all?(&:code_review_enabled?)
        end

        # If any of the orgs enable the policy, access is enabled
        copilot_organizations.any? do |org|
          org.code_review_enabled?
        end
      end

      sig { override.returns(String) }
      def chat_setting
        return "enabled" if chat_enabled?
        return "disabled" if chat_disabled?
        "unconfigured"
      end

      sig { override.returns(String) }
      def pr_summarizations
        return "enabled" if pr_summarizations_enabled?
        return "disabled" if pr_summarizations_disabled?
        "unconfigured"
      end

      sig { override.returns(String) }
      def private_docs
        return "enabled" if private_docs_enabled?
        return "disabled" if private_docs_disabled?
        "unconfigured"
      end

      sig { returns(T::Boolean) }
      def annotations_enabled?
        user_object.feature_flag_enabled_or_raise?(:copilot_annotations) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      sig { returns(T::Boolean) }
      def snippy_load_test_enabled?
        user_object.feature_flag_enabled_or_raise?(:copilot_snippy_load_test_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      sig { void }
      def enable_telemetry!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.user_telemetry_enabled!
        end
        GitHub.dogstats.increment("copilot.settings.telemetry_enabled", tags: ["type:user"])
      end

      sig { override.void }
      def enable_chat!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(chat_enabled: :enabled)
        end

        GitHub.dogstats.increment(
          "copilot.settings.chat_enabled_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def disable_chat!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(chat_enabled: :disabled)
        end

        GitHub.dogstats.increment(
          "copilot.settings.chat_enabled_disabled",
          tags: ["type:user"],
        )
      end

      sig { returns(String) }
      def copilot_for_dotcom
        if copilot_for_dotcom_enabled?
          "enabled"
        elsif copilot_for_dotcom_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias copilot_for_dotcom_setting copilot_for_dotcom

      sig { override.returns(T::Boolean) }
      def copilot_for_dotcom_configured?
        return true if copilot_organizations.any?(&:copilot_for_dotcom_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.copilot_for_dotcom_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_for_dotcom_unconfigured?
        configuration.copilot_for_dotcom_unconfigured?
      end

      sig { override.void }
      def copilot_for_dotcom_unconfigured!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_unconfigured!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_unconfigured",
          tags: ["type:user"],
        )
      end

      sig { override.returns(T::Boolean) }
      def copilot_for_dotcom_enabled?
        user_object.businesses.each do |business|
          return false if Copilot::Business.new(business).copilot_for_dotcom_disabled?
        end

        return true if copilot_organizations.any?(&:copilot_for_dotcom_enabled?)

        return false if copilot_organizations.any? && copilot_organizations.all?(&:copilot_for_dotcom_disabled?)

        configuration.copilot_for_dotcom_enabled?
      end

      sig { override.void }
      def copilot_for_dotcom_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.returns(T::Boolean) }
      def copilot_for_dotcom_disabled?
        return true if copilot_organizations.any?(&:copilot_for_dotcom_disabled?)

        return false if copilot_organizations.any?(&:copilot_for_dotcom_enabled?)

        configuration.copilot_for_dotcom_disabled?
      end

      sig { override.void }
      def copilot_for_dotcom_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_for_dotcom_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.returns(T::Boolean) }
      def copilot_for_dotcom_no_policy?
        configuration.copilot_for_dotcom_no_policy?
      end

      sig { override.void }
      def copilot_for_dotcom_no_policy!
        # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_no_policy",
          tags: ["type:user"],
        )
      end

      sig { void }
      def disable_telemetry!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.user_telemetry_disabled!
        end

        GitHub.dogstats.increment("copilot.settings.telemetry_disabled", tags: ["type:user"])
      end

      sig { override.returns(T::Boolean) }
      def telemetry_enabled?
        debug_logging = FeatureFlag.vexi.enabled?(:copilot_token_service_telemetry_debug, user_object, default: false)

        if GitHub.multi_tenant_enterprise?
          is_staff_stamp = GitHub.copilot_stamp&.start_with?("staff-") || false
          if debug_logging
            GitHub.logger.info(
              "Copilot telemetry_enabled check",
              "gh.user.analytics_tracking_id" => user_object.analytics_tracking_id,
              "gh.copilot.telemetry.reason" => "multi_tenant_enterprise",
              "gh.copilot.telemetry.enabled" => is_staff_stamp,
              "gh.copilot.stamp" => GitHub.copilot_stamp,
            )
          end
          return is_staff_stamp
        end

        if telemetry_required?
          if debug_logging
            GitHub.logger.info(
              "Copilot telemetry_enabled check",
              "gh.user.analytics_tracking_id" => user_object.analytics_tracking_id,
              "gh.copilot.telemetry.reason" => "telemetry_required_for_org",
              "gh.copilot.telemetry.enabled" => true,
            )
          end
          return true
        end

        if copilot_for_business_enabled?
          if debug_logging
            GitHub.logger.info(
              "Copilot telemetry_enabled check",
              "gh.user.analytics_tracking_id" => user_object.analytics_tracking_id,
              "gh.copilot.telemetry.reason" => "copilot_for_business_enabled",
              "gh.copilot.telemetry.enabled" => false,
            )
          end
          return false
        end

        result = ActiveRecord::Base.connected_to(role: :reading) do
          configuration.user_telemetry_enabled?
        end

        if debug_logging
          GitHub.logger.info(
            "Copilot telemetry_enabled check",
            "gh.user.analytics_tracking_id" => user_object.analytics_tracking_id,
            "gh.copilot.telemetry.reason" => "user_configuration",
            "gh.copilot.telemetry.enabled" => result,
          )
        end

        result
      end

      sig { override.returns(T::Boolean) }
      def telemetry_required?
        user_orgs = user_object.organization_ids || []
        (COPILOT_TELEMETRY_ORG_IDS & user_orgs).any?
      end

      sig { returns(T.nilable(Copilot::Organization)) }
      def fine_tuning_organization
        enabled = copilot_organizations.all?(&:private_telemetry_enabled?)
        return nil unless enabled

        # At this point this is very naive, they maybe in multiple orgs
        # and we do not know which one will get the fine tuning feature
        # if we are luck the first org in the list will get it, then
        # we will have telemetry to train with. But if we are not lucky
        # then we accredit this telemetry to the wrong org.
        copilot_org = copilot_organizations.first

        # We need to figure out which custom model they are using
        # They could be using a custom model from an org that is not
        # the first org in the list, if they are using a custom model
        # we want to make sure we accredit the telemetry to the org
        # the custom model is from. So we can train with it.
        # This is also naive at this point, they could have more
        # than one custom model, and we do not know which one
        # the will use if given a choice. We will just pick the
        # first one in the list since that is what legacy vscode does.
        custom_models = Orca::Model.for_organizations(
          copilot_organizations.map(&:organization_object)
        )
        return copilot_org unless custom_models.any?

        custom_model = custom_models.first
        org = custom_model&.organization
        return copilot_org unless org

        Copilot::Organization.new(org)
      end

      # This returns a list of organizations that have fine tuning enabled and
      # have enabled private telemetry collection. This is guarded by the
      # copilot_custom_models_multi_ft feature flag in the envelope. IF
      # enabled, the analytics tracking IDs of these orgs will be used for
      # attributing custom telemetry collection.
      sig { returns(T::Array[Copilot::Organization]) }
      def fine_tuning_organizations
        copilot_organizations.select(&:private_telemetry_enabled?)
      end

      sig { returns(T.nilable(::Organization)) }
      def rag_organization
        user_object.organizations.find do |org|
          org.feature_flag_enabled_or_raise?(:copilot_retrieval_alpha_org) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        end
      end

      sig { override.returns(String) }
      def telemetry_setting
        if telemetry_enabled?
          "enabled"
        else
          "disabled"
        end
      end

      sig { override.returns(Configurable) }
      def configurable_object
        user_object
      end

      sig { override.returns(String) }
      def copilot_plan
        return "business" if has_copilot_standalone_business?

        # Enterprise-assigned users won't have an organization but they will have a business
        # and they're always on the business plan.
        return "individual" if copilot_organizations.empty? && copilot_businesses.empty?

        # If any org is on the enterprise plan this user has Copilot Enterprise
        copilot_organizations.each do |org|
          return org.copilot_plan if org.copilot_plan_enterprise?
        end

        "business"
      end

      sig { returns(T::Boolean) }
      def copilot_plan_business?
        copilot_plan == "business"
      end

      sig { returns(T::Boolean) }
      def copilot_plan_enterprise?
        copilot_plan == "enterprise"
      end

      sig { override.returns(T::Boolean) }
      def copilot_plan_individual?
        copilot_plan == "individual"
      end

      sig { returns(T::Boolean) }
      def has_copilot_enterprise_access?
        copilot_enterprise_organizations.any? && dotcom_chat_enabled?
      end

      sig { override.void }
      def custom_models_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.custom_models_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.custom_models_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def custom_models_no_policy!
        # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.custom_models_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def cli_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.cli_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.cli_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def editor_preview_features_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.editor_preview_features_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.editor_preview_features_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def agent_mode_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.agent_mode_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def automatic_code_review_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.automatic_code_review_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.automatic_code_review_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o1_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o1_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o1_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o_ff_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_ff_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_ff_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def custom_models_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.custom_models_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.custom_models_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def cli_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.cli_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.cli_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def cli_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.cli_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def editor_preview_features_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.editor_preview_features_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.editor_preview_features_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def editor_preview_features_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.editor_preview_features_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def agent_mode_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.agent_mode_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def agent_mode_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.agent_mode_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def automatic_code_review_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.automatic_code_review_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.automatic_code_review_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def automatic_code_review_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.automatic_code_review_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.returns(T::Boolean) }
      def afos_unconfigured?
        return false if copilot_organizations.any? { |org| !org.afos_unconfigured? }

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.afos_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def afos_enabled?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:afos_disabled?)
          return true if copilot_businesses.all?(&:afos_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:afos_enabled?)
          return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:afos)
          return false
        end

        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :afos)
          return configuration.afos_enabled? # you are a cfi user and you get afos
        end

        false
      end

      sig { override.returns(T::Boolean) }
      def afos_disabled?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:afos_disabled?)
          return false if copilot_businesses.all?(&:afos_enabled?)
          return false if copilot_organizations.any?(&:afos_enabled?)
          return false if business_copilot_provider_ea_user_fallback_policy_enabled?(:afos)
          return true
        end

        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, :afos)
          return configuration.afos_disabled? # you are a cfi user and you cannot disable afos
        end

        true
      end

      sig { returns(String) }
      def afos
        if afos_enabled?
          "enabled"
        elsif afos_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end

      sig { override.void }
      def afos_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.afos_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.afos_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def afos_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.afos_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.afos_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def afos_no_policy!
        # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.afos_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o1_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o1_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o1_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o1_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o1_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o_ff_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_ff_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_ff_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o_ff_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o_ff_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def pr_summarizations_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.pr_summarizations_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.pr_summarizations_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def pr_summarizations_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.pr_summarizations_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.pr_summarizations_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def pr_summarizations_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.pr_summarizations_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def private_docs_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_docs_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_docs_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def private_docs_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.private_docs_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.private_docs_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def private_docs_no_policy!
        # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.private_docs_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.returns(String) }
      def copilot_extensions
        if copilot_extensions_enabled?
          "enabled"
        else
          "disabled"
        end
      end

      sig { override.returns(T::Boolean) }
      def copilot_extensions_unconfigured?
        return false if copilot_organizations.any?(&:copilot_extensions_configured?)

        configuration.copilot_extensions_unconfigured?
      end

      sig { override.returns(T::Boolean) }
      def copilot_extensions_configured?
        return true if copilot_organizations.any?(&:copilot_extensions_configured?)

        !copilot_extensions_unconfigured?
      end

      sig { override.returns(T::Boolean) }
      def copilot_extensions_enabled?
        return false if user_object.feature_flag_enabled_or_raise?(:copilot_extensions_policy_deprecated) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return true if user_object.feature_flag_enabled_or_raise?(:copilot_extensibility_policy_override) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return true if has_limited_access? && user_object.feature_flag_enabled_or_raise?(:copilot_extension_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return true if has_cfi_access? && user_object.feature_flag_enabled_or_raise?(:copilot_extension_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return false if copilot_businesses.any?(&:copilot_extensions_disabled?) unless copilot_businesses.empty?

        return true if copilot_organizations.any?(&:copilot_extensions_enabled?)

        return false if copilot_organizations.any? && copilot_organizations.all?(&:copilot_extensions_disabled?)

        return true if business_copilot_provider_ea_user_fallback_policy_enabled?(:copilot_extensions)

        return false unless has_cfi_access?

        user_object.feature_flag_enabled_or_raise?(:copilot_extension_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      sig { override.returns(T::Boolean) }
      def copilot_extensions_disabled?
        return true if user_object.feature_flag_enabled_or_raise?(:copilot_extensions_policy_deprecated) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if user_object.feature_flag_enabled_or_raise?(:copilot_extensibility_policy_override) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if has_limited_access? && user_object.feature_flag_enabled_or_raise?(:copilot_extension_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if has_cfi_access? && user_object.feature_flag_enabled_or_raise?(:copilot_extension_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return true if copilot_businesses.any?(&:copilot_extensions_disabled?) unless copilot_businesses.empty?

        return false if copilot_organizations.any?(&:copilot_extensions_enabled?)

        return true if copilot_organizations.any? && copilot_organizations.all?(&:copilot_extensions_disabled?)

        return true unless has_cfi_access?

        !user_object.feature_flag_enabled_or_raise?(:copilot_extension_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      sig { override.void }
      def copilot_extensions_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_extensions_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_extensions_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def copilot_extensions_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.copilot_extensions_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_extensions_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def mcp_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.mcp_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.mcp_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def mcp_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.mcp_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.mcp_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def mcp_no_policy!
        GitHub.dogstats.increment(
          "copilot.settings.mcp_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def spark_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.spark_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.spark_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def spark_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.spark_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.spark_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def spark_no_policy!
        # There is no no-policy Spark setting at the user level but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.spark_no_policy",
          tags: ["type:user"],
        )
      end

      sig { params(copilot_user: Copilot::User).void }
      def set_free_plan_defaults!(copilot_user)
        # We will put the settings here for simplicity
        copilot_user.allow_public_code_suggestions!
        copilot_user.enable_telemetry!
      end

      sig { override.returns(T::Boolean) }
      def dashboard_entry_point_enabled?
        user_object.settings.get(:copilot_dashboard_entry_point_enabled)
      end

      sig { override.void }
      def dashboard_entry_point_enabled!
        return if dashboard_entry_point_enabled?
        ActiveRecord::Base.connected_to(role: :writing) do
          user_object.settings.set!(:copilot_dashboard_entry_point_enabled, true)
        end

        GitHub.dogstats.increment(
          "copilot.settings.dashboard_entry_point_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def dashboard_entry_point_disabled!
        return unless dashboard_entry_point_enabled?
        ActiveRecord::Base.connected_to(role: :writing) do
          user_object.settings.set!(:copilot_dashboard_entry_point_enabled, false)
        end

        GitHub.dogstats.increment(
          "copilot.settings.dashboard_entry_point_disabled",
          tags: ["type:user"],
        )

      end

      sig { override.void }
      def overages_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.overages_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.overages_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def overages_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.overages_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.overages_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def overages_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.overages_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def swe_agent_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.swe_agent_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.swe_agent_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def swe_agent_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.swe_agent_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.swe_agent_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def swe_agent_no_policy!
        # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.swe_agent_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def code_review_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.code_review_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.code_review_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def code_review_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.code_review_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.code_review_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def code_review_no_policy!
        # the code review policy does not exist at the user level but we'll track it in case we goofed and wound up here
        GitHub.dogstats.increment("copilot.settings.code_review_no_policy", tags: ["type:user"])
      end

      sig { override.void }
      def insights_enabled!
        # there is no concept of insights at the user level but we'll track it in case we goofed and wound up here
        GitHub.dogstats.increment("copilot.settings.insights_enabled", tags: ["type:user"])
      end

      sig { override.void }
      def insights_disabled!
        # there is no concept of insights at the user level but we'll track it in case we goofed and wound up here
        GitHub.dogstats.increment("copilot.settings.insights_disabled", tags: ["type:user"])
      end

      sig { override.void }
      def insights_no_policy!
        # there is no concept of insights at the user level but we'll track it in case we goofed and wound up here
        GitHub.dogstats.increment("copilot.settings.insights_no_policy", tags: ["type:user"])
      end

      sig { override.returns(T::Boolean) }
      def show_copilot_enabled?
        user_object.settings.get(:copilot_show_functionality)
      end

      sig { override.void }
      def show_copilot_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          user_object.settings.set!(:copilot_show_functionality, true)
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_show_functionality_enabled",
          tags: ["type:user"],
        )

        Copilot::Instrumenter.instrument_show_copilot(
          user_object,
        )
      end

      sig { override.void }
      def show_copilot_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          user_object.settings.set!(:copilot_show_functionality, false)
        end

        GitHub.dogstats.increment(
          "copilot.settings.copilot_show_functionality_disabled",
          tags: ["type:user"],
        )

        Copilot::Instrumenter.instrument_hide_copilot(
          user_object,
        )
      end

      sig { params(id: T.nilable(Integer)).void }
      def set_billable_customer_id!(id)
        copilot_user = Copilot::Public::User.new(user_object)
        if id.present? && !copilot_user.copilot_customer_ids.include?(id)
          # Don't set a billable customer ID that isn't in the list of customer IDs
          return
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(billable_customer_id: id)
        end

        Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(copilot_user)
      end

      sig { override.void }
      def generated_commit_message_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.generated_commit_message_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.generated_commit_message_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def generated_commit_message_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.generated_commit_message_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.generated_commit_message_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def generated_commit_message_no_policy!
        # the generated commit message no policy does not exist at the user level but we'll track it in case we goofed and wound up here
        GitHub.dogstats.increment("copilot.settings.generated_commit_message_no_policy", tags: ["type:user"])
      end

      sig { returns(T::Boolean) }
      def generated_commit_message_configurable_by_user?
        return true if has_cfi_access?

        return true if copilot_businesses.any?(&:generated_commit_message_enabled?) || copilot_organizations.any?(&:generated_commit_message_enabled?) || business_copilot_provider_ea_user_fallback_policy_enabled?(:generated_commit_message)

        false
      end

      sig { override.returns(T::Boolean) }
      def generated_commit_message_enabled?
        if has_cfb_access?
          # If any of their businesses or orgs have it enabled, the user can configure the setting
          return generated_commit_message_enabled_with_default? if generated_commit_message_configurable_by_user?

          return false
        end

        generated_commit_message_enabled_with_default?
      end

      sig { returns(T::Boolean) }
      def generated_commit_message_enabled_with_default?
        # Exisiting users' configuration won't be defaulted to enabled
        # So if their configuration is unconfigured, we should return enabled to reflect the desired default behavior for users which is enabled
        # New users will have it set by Copilot::Users::Settings#configuration_defaults
        configuration.generated_commit_message_enabled? || configuration.generated_commit_message_unconfigured?
      end

      sig { override.returns(T::Boolean) }
      def generated_commit_message_disabled?
        if has_cfb_access?
          # If any of their businesses or orgs have it enabled, the user can configure the setting
          return !generated_commit_message_enabled_with_default? if generated_commit_message_configurable_by_user?

          # If none of their businesses or orgs have it enabled, they don't get it
          return true
        end

        configuration.generated_commit_message_disabled?
      end

      # This method is used to determine if a policy is enabled as Least Restrictive for top tier models such as o3 and 4.5
      sig { override.params(policy_symbol: Symbol, is_enabled_proc: Proc, is_disabled_proc: Proc).returns(T::Boolean) }
      def least_restrictive_premium_enabled?(policy_symbol:, is_enabled_proc:, is_disabled_proc:)
        # Check for users part of orgs
        if has_cfe_access?
          # If any of the businesses disable the model, the user gets disabled
          return false if copilot_businesses.any?(is_disabled_proc)
          # If any of the orgs with CFE enable the model, the user gets enabled (least restrictive)
          return true if copilot_enterprise_organizations.any?(is_enabled_proc)
          return true if copilot_businesses.all?(is_enabled_proc) unless copilot_businesses.empty?
          return false
        end

        # Check for users with individual licenses
        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, policy_symbol)
          if (has_max_access? || has_pro_plus_access?) && user_object.feature_flag_enabled_or_raise?("copilot_#{policy_symbol}_cfi_on".to_sym) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return true
          end

          return configuration.send("#{policy_symbol}_enabled?")
        end

        false
      end

      # This method is used to determine if a policy is disabled as Least Restrictive for top tier models such as o3 and 4.5
      sig { override.params(policy_symbol: Symbol, is_enabled_proc: Proc, is_disabled_proc: Proc).returns(T::Boolean) }
      def least_restrictive_premium_disabled?(policy_symbol:, is_enabled_proc:, is_disabled_proc:)
        # Check for users part of orgs
        if has_cfe_access?
          return true if copilot_businesses.any?(is_disabled_proc)
          return false if copilot_businesses.all?(is_enabled_proc)
          return false if copilot_enterprise_organizations.any?(is_enabled_proc)
          return true
        end

        # Check for users with individual licenses
        if Copilot::Users::ModelAccess.model_available?(copilot_user_object, policy_symbol)
          if (has_max_access? || has_pro_plus_access?) && user_object.feature_flag_enabled_or_raise?("copilot_#{policy_symbol}_cfi_on".to_sym) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return false
          end

          return configuration.send("#{policy_symbol}_disabled?")
        end

        true
      end

      sig { returns(T::Boolean) }
      def codex_agent_enabled?
        # The FF allows us to bypass other checks for staff and other specific users.
        return true if user_object.feature_flag_enabled?(:copilot_codex_agent_allowlist, default: false)

        # Initially this will be enabled for Pro+ users only. Eventually we will support more SKUs and specifically
        # CB/CE access, but will require a setting/policy for that.
        return false unless has_pro_plus_access?
        return true if user_object.feature_flag_enabled?(:copilot_codex_agent, default: false)

        false
      end

      sig { params(include_trials: T::Boolean).returns(T.nilable(Copilot::Plan)) }
      def copilot_plan_enum(include_trials: true)
        return nil unless include_trials || !copilot_authorizer_object_no_snippy.has_trial_access?

        if has_cfi_access?
          if has_limited_access?
            Copilot::Plans::CFI::Free
          elsif has_pro_access?
            Copilot::Plans::CFI::Pro
          elsif has_pro_plus_access?
            Copilot::Plans::CFI::ProPlus
          elsif has_max_access?
            Copilot::Plans::CFI::Max
          else
            # if you got here, you have complimentary access
            Copilot::Plans::CFI::Pro
          end
        elsif has_cfe_access?
          Copilot::Plans::CFB::Enterprise
        elsif has_standalone_access?
          Copilot::Plans::CFB::StandaloneBusiness
        elsif copilot_authorizer_object_no_snippy.has_cfb_access?
          # this check must be after cfe as cfe includes cfb access
          # also opting to use the authorizer for Copilot::User objects since it will already have been loaded
          Copilot::Plans::CFB::NonStandaloneBusiness
        end
      end

      sig { params(min_cfi_plan: T.nilable(Copilot::Plans::CFI), min_cfb_plan: T.nilable(Copilot::Plans::CFB), include_trials: T::Boolean).returns(T::Boolean) }
      def copilot_plan_at_least?(min_cfi_plan:, min_cfb_plan:, include_trials: true)
        plan = copilot_plan_enum(include_trials: include_trials)
        return false if plan.nil?
        plan.at_least?(min_cfi_plan) || plan.at_least?(min_cfb_plan)
      end

      sig { override.returns(T::Hash[Symbol, T.any(Integer, Symbol)]) }
      def configuration_defaults
        return configuration_defaults_candidate if user_object.feature_flag_enabled?(:copilot_policy_class_defaults_migration, default: false)

        defaults = {
          user_telemetry: :enabled,
          chat_enabled: :enabled,
          mobile_chat: :disabled,
          dotcom_chat: :unconfigured,
          max_seats: 0,
          usage_telemetry_api: :disabled,
          copilot_plan: :unconfigured,
          cli: :unconfigured,
          bing_github_chat: :enabled,
          desktop: :unconfigured,
          overages: :unconfigured,
          swe_agent: :disabled,
          mcp: :disabled,
          spark: :disabled,
          insights: :unconfigured,
          public_code_suggestions: :allowed,
          code_review: :unconfigured,
          generated_commit_message: :enabled,
          agent_mode: :enabled,
          agent_mode_auto_approve: :enabled,
        }

        # NOTE: This configuration default tweak can be removed after the migration is complete
        # It is for an experiment to enable SWE Agent for a portion of limited tier users
        # and this behavior is already configured on the policy object itself
        if limited_tier_has_swe_agent_access?(use_cache_only: true)
          defaults[:swe_agent] = :enabled
        end

        if user_object.feature_flag_enabled?(:copilot_policy_class_defaults, default: false)
          defaults.reverse_merge(Copilot::Policies.configuration_defaults(T.bind(self, Copilot::User)))
        else
          defaults
        end
      end

      sig { returns(T::Hash[Symbol, T.any(Integer, Symbol)]) }
      def configuration_defaults_candidate
        defaults = {
          user_telemetry: :enabled,
          max_seats: 0,
          copilot_plan: :unconfigured,
          overages: :unconfigured,
        }

        defaults.merge(Copilot::Policies.configuration_defaults(T.bind(self, Copilot::User)))
      end

      sig { params(use_cache_only: T::Boolean).returns(T::Boolean) }
      def limited_tier_has_swe_agent_access?(use_cache_only: false)
        ActiveRecord::Base.connected_to(role: :reading) do
          return false unless has_limited_access?

          AzureEXP::Experiments::CopilotGrowth.in_free_cca_experiment?(user_object, use_cache_only: use_cache_only)
        end
      end
    end
  end
end
