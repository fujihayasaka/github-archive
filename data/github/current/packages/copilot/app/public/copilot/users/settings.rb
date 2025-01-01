# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Settings
      extend T::Helpers

      abstract!

      include Copilot::Users::Signatures
      include HasConfiguration
      include GitHub::Memoizer

      delegate :dotcom_chat_no_policy?, :dotcom_chat_unconfigured?,
               :custom_models, :custom_models_disabled?, :custom_models_enabled?, :custom_models_no_policy?,
               :custom_models_configured?, :custom_models_unconfigured?,
               :cli_no_policy?, :cli_unconfigured?, :private_telemetry, :private_telemetry_unconfigured?, :private_telemetry_configured?,
               :private_telemetry_no_policy?, :private_telemetry_enabled?, :private_telemetry_disabled?, :private_telemetry_disabled!,
               :private_telemetry_enabled!, :private_telemetry_no_policy!, :private_telemetry_setting,
               :pr_summarizations_no_policy?, :private_docs_no_policy?, :mobile_chat_no_policy?, :copilot_extensions_no_policy?,
               :editor_preview_features_no_policy?, :editor_preview_features_unconfigured?,
               :a_chat_no_policy?, :a_chat_unconfigured?,
               :a_f_no_policy?, :a_f_unconfigured?,
               :g_chat_no_policy?, :g_chat_unconfigured?,
               :o1_no_policy?, :o1_unconfigured?,
               :o3_no_policy?, :o3_unconfigured?,
               :o_ff_no_policy?, :o_ff_unconfigured?,
               :o_f_no_policy?, :o_f_unconfigured?,
               :desktop_no_policy?, :desktop_unconfigured?,
               :overages_no_policy?, :overages_unconfigured?,
               to: :configuration

      alias custom_models_setting custom_models

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
          when :a_chat
            return configuration.a_chat_enabled?
          when :a_f
            return configuration.a_f_enabled?
          when :g_chat
            return configuration.g_chat_enabled?
          when :o1
            return false if has_limited_access?
            return configuration.o1_enabled?
          when :o3
            return configuration.o3_enabled?
          when :o_ff
            return configuration.o_ff_enabled?
          when :o_f
            return configuration.o_f_enabled?
          when :bing_github_chat
            return bing_github_chat_enabled?
          when :overages
            return false if has_limited_access?
            return configuration.overages_enabled?
          end
        end

        if policy == :public_code_suggestions || policy == :public_code_suggestions_enabled
          return allow_public_code_suggestions?
        end
        case policy
        when :cli, :dotcom_chat, :chat_enabled, :pr_summarizations, :private_docs, :copilot_for_dotcom, :copilot_extensions, :beta_features_github_chat, :editor_preview_features, :a_chat, :g_chat, :o1, :o3, :a_f, :o_ff, :o_f, :desktop
          copilot_user.enabled_least_restrictive?(all_policies, policy)
        when :overages
          copilot_user.enabled_true_least_restrictive?(all_policies, policy)
        when :bing_github_chat, :mobile_chat
          copilot_user.enabled_most_restrictive?(all_policies, policy)
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
          when :a_chat
            return configuration.a_chat_disabled?
          when :a_f
            return configuration.a_f_disabled?
          when :g_chat
            return configuration.g_chat_disabled?
          when :o1
            return true if has_limited_access?
            return configuration.o1_disabled?
          when :o3
            return configuration.o3_disabled?
          when :o_ff
            return configuration.o_ff_disabled?
          when :o_f
            return configuration.o_f_disabled?
          when :copilot_extensions
            return true unless has_cfi_access?

            return !user_object.feature_enabled?(:copilot_extension_access)
          when :bing_github_chat
            return bing_github_chat_disabled?
          when :overages
            return true if has_limited_access?
            return configuration.overages_disabled?
          end
        end

        if policy == :public_code_suggestions || policy == :public_code_suggestions_enabled
          return block_public_code_suggestions?
        end

        case policy
        when :cli, :dotcom_chat, :chat_enabled, :pr_summarizations, :private_docs, :copilot_for_dotcom, :copilot_extensions, :editor_preview_features_disabled, :a_chat, :g_chat, :o1, :o3, :a_f, :o_ff, :o_f, :desktop
          copilot_user.disabled_least_restrictive?(all_policies, policy)
        when :bing_github_chat, :mobile_chat
          copilot_user.disabled_most_restrictive?(all_policies, policy)
        when :overages
          copilot_user.disabled_true_least_restrictive?(all_policies, policy)
        else
          copilot_user.disabled_most_restrictive?(all_policies, policy)
        end
      end

      sig { override.returns(T::Boolean) }
      def workspace_enabled?
        return false unless user_object.feature_enabled?(:copilot_workspace)

        if user_object.is_enterprise_managed?
          !!copilot_business&.workspace_for_emu_enabled?
        else
          true
        end
      end

      sig { override.returns(T::Boolean) }
      def spark_enabled?
        user_object.feature_enabled?(:github_spark)
      end

      sig { override.returns(T::Boolean) }
      def beta_features_github_chat_disabled?
        !beta_features_github_chat_enabled?
      end

      sig { override.returns(T::Boolean) }
      memoize def beta_features_github_chat_enabled?
        return false if has_limited_access?
        return true if has_cfi_access?
        return false unless copilot_organizations.any?
        copilot_organizations.all? { |org| org.beta_features_github_chat_enabled? }
      end

      sig { override.returns(T::Boolean) }
      def bing_github_chat_disabled?
        !bing_github_chat_enabled?
      end

      sig { override.returns(T::Boolean) }
      def bing_github_chat_enabled?
        if copilot_plan_individual?
          return ActiveRecord::Base.connected_to(role: :reading) do
            configuration.bing_github_chat_enabled?
          end
        end

        # Standalone businesses can also provide this policy to users.
        if copilot_businesses.size > 0
          return false if copilot_businesses.any?(&:bing_github_chat_disabled?)
          return true if copilot_businesses.all?(&:bing_github_chat_enabled?)
        end

        return false if copilot_organizations.empty?
        copilot_organizations.all? { |org| org.bing_github_chat_enabled? }
      end

      sig { void }
      def bing_github_chat_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.bing_github_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.bing_github_chat_enabled",
          tags: ["type:user"],
        )
      end

      sig { void }
      def bing_github_chat_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.bing_github_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.bing_github_chat_disabled",
          tags: ["type:user"],
        )
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

      # So, funny story. Snippy is the name of a tool that is used to redact code suggestions from public sources
      # It can be ENABLED or DISABLED.
      # In the UI, we use the terms ALLOW/BLOCK and make the mistake of thinking those mapped to
      # ENABLED and DISABLED respectively.
      #
      # They didn't - they map to the inverse.
      #
      # If you want to ALLOW public code suggestions, you need to DISABLE snippy.
      # If you want to BLOCK public code suggestions, you need to ENABLE snippy.
      sig { override.returns(T::Boolean) }
      def public_code_suggestions_configured?
        return true if copilot_organizations.any?(&:public_code_suggestions_configured?)
        return true if has_copilot_standalone_business? && copilot_businesses.any?(&:public_code_suggestions_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_configured?
        end
      end

      # Returns the effective allow setting for snippy. The user can configure
      # this for Copilot, or it can be inherited from an Organization or
      # Business via seats.
      sig { override.returns(T::Boolean) }
      def allow_public_code_suggestions?
        return false if copilot_organizations.any?(&:block_public_code_suggestions?)
        return true if copilot_organizations.any?(&:allow_public_code_suggestions?)

        return false if copilot_businesses.any?(&:block_public_code_suggestions?)
        return true if copilot_businesses.any?(&:allow_public_code_suggestions?)

        # snippy is disabled
        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_allowed?
        end
      end

      sig { returns(T::Boolean) }
      def codequote_enabled?
        # Flag to get around code referencing blocks for certain orgs e.g. GitHub
        return true if user_object.feature_enabled?(:copilot_force_code_references)
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

      sig { override.returns(T::Boolean) }
      memoize def has_completions_quota_remaining?
        return true unless has_limited_access?

        limited_user = Copilot::LimitedUser.find_by(user: user_object)
        return false unless limited_user.present?

        limited_user.feature_allowed?(feature: "completions")
      end

      sig { override.returns(T::Boolean) }
      memoize def has_chat_quota_remaining?
        # this is super duper important because if they aren't
        # a limited user they have to return true here
        return true unless has_limited_access?
        return false unless limited_user.present?

        T.must(limited_user).feature_allowed?(feature: "chat")
      end

      sig { override.returns(T::Array[CopilotQuotaDetail]) }
      def quota_details
        return [] unless has_limited_access?
        return [] unless limited_user.present?

        T.must(limited_user).quotas_remaining.map do |feature, remaining|
          feature_monthly_quota = Copilot::Quotas.monthly_quotas[feature].to_f
          {
            feature: feature,
            quota: remaining,
            percentage: (remaining.to_f / feature_monthly_quota) * 100.0,
          }
        end
      end

      sig { override.returns(T::Boolean) }
      def dotcom_chat_configured?
        return true if copilot_organizations.any?(&:dotcom_chat_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.dotcom_chat_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def dotcom_chat_enabled?
        GitHub.tracer.in_span("copilot_user.dotcom_chat_enabled?") do |_span|
          # Todo: uncomment after updating default config value to unconfigured.
          # return false if configuration.dotcom_chat_disabled?
          return false if copilot_businesses.any?(&:dotcom_chat_disabled?)
          return true if copilot_businesses.all?(&:dotcom_chat_enabled?) unless copilot_businesses.empty?

          return true if copilot_organizations.any?(&:dotcom_chat_enabled?)

          return false if copilot_organizations.count > 0 && copilot_organizations.all?(&:dotcom_chat_disabled?)
          # if they have CI then dotcom chat is always enabled
          # otherwise we fall through to their cached settings
          return true if has_ci_access?

          configuration.dotcom_chat_enabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def dotcom_chat_disabled?
        # Todo: uncomment after updating default config value to unconfigured.
        # return true if configuration.dotcom_chat_disabled?

        return true if copilot_businesses.any?(&:dotcom_chat_disabled?)

        return false if copilot_organizations.any?(&:dotcom_chat_enabled?)

        return true if copilot_organizations.count > 0 && copilot_organizations.all?(&:dotcom_chat_disabled?)

        # Todo: remove after updating default config value to unconfigured.
        configuration.dotcom_chat_disabled?
      end

      sig { returns(T::Boolean) }
      memoize def has_knowledge_bases?
        has_copilot_enterprise_access?
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
      alias mobile_chat_setting mobile_chat

      sig { override.void }
      def enable_mobile_chat!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(mobile_chat: :enabled)
        end

        GitHub.dogstats.increment(
          "copilot.settings.mobile_chat_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def disable_mobile_chat!
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
        return true if user_object.feature_enabled?(:copilot_mobile_chat)

        if has_cfb_access?
          # ENTERPRISE CHECKS
          return false if copilot_businesses.any?(&:mobile_chat_disabled?)
          return true if copilot_businesses.all?(&:mobile_chat_enabled?) unless copilot_businesses.empty?

          # ORGANIZATION CHECKS
          # If ANY of the orgs that a user belongs to or any of the enterprises associated with those orgs have disabled mobile chat,
          # the user gets mobile_chat_disabled
          return false if copilot_organizations.any?(&:mobile_chat_disabled?)

          # Otherwise, the user gets mobile chat enabled
          return true
        end

        return false if has_limited_access? && !user_object.feature_enabled?(:copilot_free_mobile)
        has_cfi_access? # you are a cfi user and you get mobile chat
      end

      sig { override.returns(T::Boolean) }
      def mobile_chat_disabled?
        return false if user_object.feature_enabled?(:copilot_free_mobile)

        if has_cfb_access?
          # ENTERPRISE CHECKS
          # If a user belongs to a business that has disabled mobile chat, the user gets mobile_chat_disabled
          return true if copilot_businesses.any?(&:mobile_chat_disabled?)

          # ORGANIZATION CHECKS
          # If ANY of the orgs that a user belongs to or any of the enterprises associated with those orgs have disabled mobile chat
          # the user gets mobile_chat_disabled
          return true if copilot_organizations.any?(&:mobile_chat_disabled?)

          # Otherwise, the user gets mobile chat enabled
          return false
        end

        # you are a cfi user you get mobile chat whether you like it or not
        return true if has_limited_access? && !user_object.feature_enabled?(:copilot_free_mobile)
        !has_cfi_access?
      end

      sig { returns(T::Boolean) }
      def unconfigured_dotcom_chat?
        configuration.dotcom_chat_unconfigured?
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
        return false if has_limited_access? && !user_object.feature_enabled?(:copilot_free_cli)
        return true if has_cfi_access?

        return false if copilot_businesses.any?(&:cli_disabled?)
        return true if copilot_businesses.all?(&:cli_enabled?) unless copilot_businesses.empty?

        return true if copilot_organizations.any?(&:cli_enabled?)
        return false if copilot_organizations.count > 0 && copilot_organizations.all?(&:cli_disabled?)

        false
      end

      sig { override.returns(T::Boolean) }
      def cli_disabled?
        return true if has_limited_access? && !user_object.feature_enabled?(:copilot_free_cli)
        return false if has_cfi_access?

        # If any non-business in which the user has a Copilot seat has disabled this
        # feature, it is disabled for the user.
        return true if copilot_businesses.any?(&:cli_disabled?)

        return false if copilot_organizations.any?(&:cli_enabled?)
        return true if copilot_organizations.count > 0 && copilot_organizations.all?(&:cli_disabled?)

        configuration.cli_disabled?
      end

      sig { returns(String) }
      def cli
        if cli_enabled?
          "enabled"
        elsif cli_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias cli_setting cli

      sig { override.returns(T::Boolean) }
      def desktop_configured?
        return true if copilot_organizations.any?(&:desktop_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.desktop_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def desktop_enabled?
        return false unless user_object.feature_enabled?(:copilot_desktop)

        return false if has_limited_access? && !user_object.feature_enabled?(:copilot_free_desktop)
        return true if has_cfi_access?

        return false if copilot_businesses.any?(&:desktop_disabled?)
        return true if copilot_businesses.all?(&:desktop_enabled?) unless copilot_businesses.empty?

        return true if copilot_organizations.any?(&:desktop_enabled?)
        return false if copilot_organizations.count > 0 && copilot_organizations.all?(&:desktop_disabled?)

        false
      end

      sig { override.returns(T::Boolean) }
      def desktop_disabled?
        return true unless user_object.feature_enabled?(:copilot_desktop)

        return true if has_limited_access? && !user_object.feature_enabled?(:copilot_free_desktop)
        return false if has_cfi_access?

        # If any non-business in which the user has a Copilot seat has disabled this
        # feature, it is disabled for the user.
        return true if copilot_businesses.any?(&:desktop_disabled?)

        return false if copilot_organizations.any?(&:desktop_enabled?)
        return true if copilot_organizations.count > 0 && copilot_organizations.all?(&:desktop_disabled?)

        configuration.desktop_disabled?
      end

      sig { returns(String) }
      def desktop
        if desktop_enabled?
          "enabled"
        elsif desktop_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias desktop_setting desktop

      sig { override.returns(T::Boolean) }
      def editor_preview_features_configured?
        return true if copilot_organizations.any?(&:editor_preview_features_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.editor_preview_features_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def editor_preview_features_enabled?
        return false unless user_object.feature_enabled?(:copilot_next_edit_suggestions)

        return true if has_limited_access? || has_cfi_access?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:editor_preview_features_disabled?)
          return true if copilot_businesses.all?(&:editor_preview_features_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:editor_preview_features_enabled?)
          return false
        end

        configuration.editor_preview_features_enabled? # you are a cfi user and you get NES
      end

      sig { override.returns(T::Boolean) }
      def editor_preview_features_disabled?
        return true unless user_object.feature_enabled?(:copilot_next_edit_suggestions)
        return false if has_limited_access? || has_cfi_access?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:editor_preview_features_disabled?)
          return false if copilot_businesses.all?(&:editor_preview_features_enabled?)
          return false if copilot_organizations.any?(&:editor_preview_features_enabled?)
          return true
        end

        configuration.editor_preview_features_disabled? # you are a cfi user and you cannot disable next edit suggestions
      end

      sig { returns(String) }
      def editor_preview_features
        if editor_preview_features_enabled?
          "enabled"
        elsif editor_preview_features_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias editor_preview_features_setting editor_preview_features

      sig { override.returns(T::Boolean) }
      def a_chat_configured?
        return true if copilot_organizations.any?(&:a_chat_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.a_chat_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def a_chat_enabled?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:a_chat_disabled?)
          return true if copilot_businesses.all?(&:a_chat_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:a_chat_enabled?)
          return false
        end

        configuration.a_chat_enabled? # you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def a_chat_disabled?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:a_chat_disabled?)
          return false if copilot_businesses.all?(&:a_chat_enabled?)
          return false if copilot_organizations.any?(&:a_chat_enabled?)
          return true
        end

        configuration.a_chat_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def a_chat
        if a_chat_enabled?
          "enabled"
        elsif a_chat_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias a_chat_setting a_chat

      sig { override.returns(T::Boolean) }
      def a_f_configured?
        return true if copilot_organizations.any?(&:a_f_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.a_f_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def a_f_enabled?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:a_f_disabled?)
          return true if copilot_businesses.all?(&:a_f_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:a_f_enabled?)
          return false
        end

        configuration.a_f_enabled? # you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def a_f_disabled?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:a_f_disabled?)
          return false if copilot_businesses.all?(&:a_f_enabled?)
          return false if copilot_organizations.any?(&:a_f_enabled?)
          return true
        end

        configuration.a_f_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def a_f
        if a_f_enabled?
          "enabled"
        elsif a_f_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias a_f_setting a_f
      alias af_setting a_f

      sig { override.returns(T::Boolean) }
      def g_chat_configured?
        return true if copilot_organizations.any?(&:g_chat_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.g_chat_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def g_chat_enabled?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:g_chat_disabled?)
          return true if copilot_businesses.all?(&:g_chat_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:g_chat_enabled?)
          return false
        end

        configuration.g_chat_enabled? # you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def g_chat_disabled?
        if has_cfb_access?
          return true if copilot_businesses.any?(&:g_chat_disabled?)
          return false if copilot_businesses.all?(&:g_chat_enabled?)
          return false if copilot_organizations.any?(&:g_chat_enabled?)
          return true
        end

        configuration.g_chat_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def g_chat
        if g_chat_enabled?
          "enabled"
        elsif g_chat_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias g_chat_setting g_chat

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
          return true
        end

        if has_cfi_access?
          return false
        end

        configuration.o1_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def o1
        if o1_enabled?
          "enabled"
        elsif o1_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias o1_setting o1

      sig { override.returns(T::Boolean) }
      def o3_configured?
        return true if copilot_organizations.any?(&:o3_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.o3_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def o3_enabled?
        return true if has_limited_access?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:o3_disabled?)
          return true if copilot_businesses.all?(&:o3_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:o3_enabled?)
          return false
        end

        if has_cfi_access?
          return true
        end

        configuration.o3_enabled? # you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def o3_disabled?
        return false if has_limited_access?

        if has_cfb_access?
          return true if copilot_businesses.any?(&:o3_disabled?)
          return false if copilot_businesses.all?(&:o3_enabled?)
          return false if copilot_organizations.any?(&:o3_enabled?)
          return true
        end

        if has_cfi_access?
          return false
        end

        configuration.o3_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def o3
        if o3_enabled?
          "enabled"
        elsif o3_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias o3_setting o3

      sig { override.returns(T::Boolean) }
      def o_ff_configured?
        return true if copilot_organizations.any?(&:o_ff_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.o_ff_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def o_ff_enabled?
        return true if has_limited_access?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:o_ff_disabled?)
          return true if copilot_businesses.all?(&:o_ff_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:o_ff_enabled?)
          return false
        end

        configuration.o_ff_enabled? # you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def o_ff_disabled?
        return false if has_limited_access?

        if has_cfb_access?
          return true if copilot_businesses.any?(&:o_ff_disabled?)
          return false if copilot_businesses.all?(&:o_ff_enabled?)
          return false if copilot_organizations.any?(&:o_ff_enabled?)
          return true
        end

        configuration.o_ff_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def o_ff
        if o_ff_enabled?
          "enabled"
        elsif o_ff_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias o_ff_setting o_ff
      alias off_setting o_ff

      sig { override.returns(T::Boolean) }
      def o_f_configured?
        return true if copilot_organizations.any?(&:o_f_configured?)

        ActiveRecord::Base.connected_to(role: :reading) do
          !configuration.o_f_unconfigured?
        end
      end

      sig { override.returns(T::Boolean) }
      def o_f_enabled?
        return true if has_limited_access?
        if has_cfb_access?
          return false if copilot_businesses.any?(&:o_f_disabled?)
          return true if copilot_businesses.all?(&:o_f_enabled?) unless copilot_businesses.empty?
          return true if copilot_organizations.any?(&:o_f_enabled?)
          return false
        end

        configuration.o_f_enabled? # you are a cfi user and you get CHAT
      end

      sig { override.returns(T::Boolean) }
      def o_f_disabled?
        return false if has_limited_access?

        if has_cfb_access?
          return true if copilot_businesses.any?(&:o_f_disabled?)
          return false if copilot_businesses.all?(&:o_f_enabled?)
          return false if copilot_organizations.any?(&:o_f_enabled?)
          return true
        end

        configuration.o_f_disabled? # you are a cfi user and you cannot disable chat
      end

      sig { returns(String) }
      def o_f
        if o_f_enabled?
          "enabled"
        elsif o_f_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias o_f_setting o_f
      alias of_setting o_f

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

        return false if copilot_organizations.count > 0 && copilot_organizations.all?(&:pr_summarizations_disabled?)

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

        return false if copilot_organizations.count > 0 && copilot_organizations.all?(&:private_docs_disabled?)

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
          return true
        end

        !configuration.overages_enabled?
      end

      sig { returns(String) }
      def overages
        if overages_enabled?
          "enabled"
        elsif overages_disabled?
          "disabled"
        else
          "unconfigured"
        end
      end
      alias overages_setting overages

      # Returns the effective block setting for snippy. The user can configure
      # this for Copilot, or it can be inherited from an Organization or
      # Business via seats.  This policy is MOST RESTRICITVE, meaning if any of the user's orgs or businesses block
      # public code suggestions, the user's setting is blocked.
      sig { override.returns(T::Boolean) }
      def block_public_code_suggestions?
        return true if copilot_organizations
          .any?(&:block_public_code_suggestions?)
        return true if copilot_businesses
          .any?(&:block_public_code_suggestions?)

        if user_object.feature_enabled?(:additional_public_code_suggestions_check)
          return false if copilot_organizations.present? && copilot_organizations
            .all?(&:allow_public_code_suggestions?)
          return false if copilot_businesses.present? && copilot_businesses
            .all?(&:allow_public_code_suggestions?)
        end

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.public_code_suggestions_blocked?
        end
      end

      # This disables snippy
      sig { override.void }
      def allow_public_code_suggestions!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(public_code_suggestions: :allowed)
        end

        GitHub.dogstats.increment(
          "copilot.settings.public_code_suggestions_allowed",
          tags: ["type:user"],
        )
      end

      # This enables snippy
      sig { override.void }
      def block_public_code_suggestions!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.public_code_suggestions_blocked!
        end

        GitHub.dogstats.increment(
          "copilot.settings.public_code_suggestions_blocked",
          tags: ["type:user"],
        )
      end

      sig { override.returns(String) }
      def snippy_setting
        return "enabled" if block_public_code_suggestions?
        return "disabled" if allow_public_code_suggestions?
        "unconfigured"
      end

      sig { override.returns(String) }
      def chat_setting
        return "enabled" if chat_enabled?
        return "disabled" if chat_disabled?
        "unconfigured"
      end

      sig { override.returns(String) }
      def dotcom_chat_setting
        return "enabled" if dotcom_chat_enabled?
        return "disabled" if dotcom_chat_disabled?
        "unconfigured"
      end

      sig { override.returns(String) }
      def pr_summarizations_setting
        return "enabled" if pr_summarizations_enabled?
        return "disabled" if pr_summarizations_disabled?
        "unconfigured"
      end

      sig { override.returns(String) }
      def private_docs_setting
        return "enabled" if private_docs_enabled?
        return "disabled" if private_docs_disabled?
        "unconfigured"
      end

      sig { returns(T::Boolean) }
      def annotations_enabled?
        user_object.feature_enabled?(:copilot_annotations)
      end

      sig { returns(T::Boolean) }
      def snippy_load_test_enabled?
        user_object.feature_enabled?(:copilot_snippy_load_test_enabled)
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

      sig { override.void }
      def dotcom_chat_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(dotcom_chat: :enabled)
        end

        GitHub.dogstats.increment(
          "copilot.settings.dotcom_chat_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def disable_dotcom_chat!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.update!(dotcom_chat: :disabled)
        end

        GitHub.dogstats.increment(
          "copilot.settings.dotcom_chat_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def dotcom_chat_no_policy!
        # no_policy is invalid for users so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.copilot_for_dotcom_no_policy",
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

        return false if copilot_organizations.count > 0 && copilot_organizations.all?(&:copilot_for_dotcom_disabled?)

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
        return false if GitHub.multi_tenant_enterprise?
        return true if telemetry_required? # telemetry is required for some orgs
        return false if copilot_for_business_enabled?

        ActiveRecord::Base.connected_to(role: :reading) do
          configuration.user_telemetry_enabled?
        end
      end

      sig { override.returns(T::Boolean) }
      def telemetry_required?
        (COPILOT_TELEMETRY_ORG_IDS & user_object.organization_ids).any?
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
          org.feature_enabled?(:copilot_retrieval_alpha_org)
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

        return "individual" if copilot_organizations.empty?

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

      sig { returns(T::Boolean) }
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
      def desktop_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.desktop_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.desktop_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def a_chat_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_disabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def a_f_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_f_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_f_disabled",
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
      def g_chat_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_chat_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_disabled",
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
      def o3_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o3_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o3_disabled",
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
      def o_f_disabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_f_disabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_f_disabled",
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
      def desktop_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.desktop_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.desktop_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def desktop_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.desktop_no_policy",
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
      def a_chat_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def a_chat_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.a_chat_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def a_f_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.a_f_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.a_f_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def a_f_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.a_f_no_policy",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def g_chat_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.g_chat_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def g_chat_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.g_chat_no_policy",
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
      def o3_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o3_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o3_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o3_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o3_no_policy",
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
      def o_f_enabled!
        ActiveRecord::Base.connected_to(role: :writing) do
          configuration.o_f_enabled!
        end

        GitHub.dogstats.increment(
          "copilot.settings.o_f_enabled",
          tags: ["type:user"],
        )
      end

      sig { override.void }
      def o_f_no_policy!
        # no_policy is invalid for orgs so we won't set it but we'll track it in case we goofed and wound up here

        GitHub.dogstats.increment(
          "copilot.settings.o_f_no_policy",
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

      sig { returns(String) }
      def copilot_extensions
        if copilot_extensions_enabled?
          "enabled"
        else
          "disabled"
        end
      end
      alias copilot_extensions_setting copilot_extensions

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
        return true if user_object.feature_enabled?(:copilot_extensibility_policy_override)
        return true if has_limited_access? && user_object.feature_enabled?(:copilot_extension_access)
        return true if has_cfi_access? && user_object.feature_enabled?(:copilot_extension_access)

        return false if copilot_businesses.any?(&:copilot_extensions_disabled?) unless copilot_businesses.empty?

        return true if copilot_organizations.any?(&:copilot_extensions_enabled?)

        return false if copilot_organizations.count > 0 && copilot_organizations.all?(&:copilot_extensions_disabled?)

        return false unless has_cfi_access?

        user_object.feature_enabled?(:copilot_extension_access)
      end

      sig { override.returns(T::Boolean) }
      def copilot_extensions_disabled?
        return false if user_object.feature_enabled?(:copilot_extensibility_policy_override)
        return false if has_limited_access? && user_object.feature_enabled?(:copilot_extension_access)
        return false if has_cfi_access? && user_object.feature_enabled?(:copilot_extension_access)

        return true if copilot_businesses.any?(&:copilot_extensions_disabled?) unless copilot_businesses.empty?

        return false if copilot_organizations.any?(&:copilot_extensions_enabled?)

        return true if copilot_organizations.count > 0 && copilot_organizations.all?(&:copilot_extensions_disabled?)

        return true unless has_cfi_access?

        !user_object.feature_enabled?(:copilot_extension_access)
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

      sig { params(copilot_user: Copilot::User).void }
      def set_free_plan_defaults!(copilot_user)
        # We will put the settings here for simplicity
        if user_object.feature_enabled?(:copilot_limit_free_user_zero_step_signup)
          # supposedly this is the final final final https://github.com/github/copilot/discussions/13492#discussioncomment-11522795
          # but you can see that we put it into the limiter redis so we can change it later if we want
          copilot_user.allow_public_code_suggestions!
          copilot_user.enable_telemetry!
        else
          # We might also have settings again
          copilot_user.block_public_code_suggestions!
          copilot_user.disable_telemetry!
        end
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

      private

      sig { override.returns(T::Hash[Symbol, T.any(Integer, Symbol)]) }
      def configuration_defaults
        {
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
          overages: :unconfigured
        }
      end
    end
  end
end
