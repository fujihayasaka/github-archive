
# typed: strict
# frozen_string_literal: true

# THIS IS A WORK IN PROGRESS. PLEASE DO NOT USE THIS FILE AS A REFERENCE FOR ANYTHING UNLESS YOU ARE WORKING ON THIS FEATURE.
# YOU CAN USE THIS ONCE THIS COMMENT IS UPDATED

module Copilot
  module Users
    module Policies
      extend T::Helpers

      include Copilot::Users::Signatures
      include GitHub::Memoizer

      # Add new policies here. The name is the key that will be stored in the user settings
      # the policy is the name of the policy we check when calling policy_enabled?
      THE_POLICIES = T.let([
          { name: :dotcom_chat_enabled, policy: :dotcom_chat },
          { name: :pr_summarizations_enabled, policy: :pr_summarizations },
          { name: :public_code_suggestions_enabled, policy: :public_code_suggestions },
          { name: :extensions_enabled, policy: :copilot_extensions },
          { name: :chat_enabled, policy: :chat_enabled },
          { name: :bing_github_chat_enabled, policy: :bing_github_chat },
          { name: :cli_enabled, policy: :cli },
          { name: :private_docs_enabled, policy: :private_docs },
          { name: :mobile_chat_enabled, policy: :mobile_chat },
          { name: :user_feedback_opt_in_enabled, policy: :user_feedback_opt_in },
          { name: :beta_features_github_chat_enabled, policy: :beta_features_github_chat },
          { name: :a_chat_enabled, policy: :a_chat },
          { name: :g_chat_enabled, policy: :g_chat },
          { name: :o1_enabled, policy: :o1 },
        ], T::Array[{ name: Symbol, policy: Symbol }])


      CopilotAllPolicies = T.type_alias do
        T::Array[
          {
            type: Symbol,
            name: String,
            id: Integer,
            config: T.nilable(Copilot::Configuration)
          }
        ]
      end

      CopilotSeatBreakdown = T.type_alias do
        {
          enabled: T::Array[{ type: Symbol, name: String }],
          disabled: T::Array[{ type: Symbol, name: String }],
          unconfigured: T::Array[{ type: Symbol, name: String }],
          no_policy: T::Array[{ type: Symbol, name: String }],
        }
      end
      abstract!

      sig { returns CopilotAllPolicies }
      def all_policies # rubocop:disable Naming/MemoizedInstanceVariableName
        collated_data = copilot_user_object.async_collated_copilot_for_business_configurations.sync
        collated_data.map do |policy_data|
          config = policy_data[:config]
          if policy_data[:business].present?
            type = :business
            name = policy_data[:business][:slug]
            id = policy_data[:business][:id]
          else
            type = :organization
            name = policy_data[:organization][:display_login]
            id = policy_data[:organization][:id]
          end
          {
            type: type,
            name: name,
            config: config,
            id: id,
          }
        end
      end

      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def enabled_most_restrictive?(policy_data, policy)
        # Copilot for Dotcom is actually a groupings of policies that includes PR Summarizations
        # so we will check that instead
        if policy == :copilot_for_dotcom
          policy = :pr_summarizations
        end

        disabled = "disabled"
        enabled = "enabled"

        if policy == :public_code_suggestions
          disabled = "blocked"
          enabled = "allowed"
        end
        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == disabled }

        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == enabled }

        false
      end

      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def disabled_most_restrictive?(policy_data, policy)
        # Copilot for Dotcom is actually a groupings of policies that includes PR Summarizations
        # so we will check that instead
        if policy == :copilot_for_dotcom
          policy = :pr_summarizations
        end

        disabled = "disabled"
        enabled = "enabled"

        if policy == :public_code_suggestions
          disabled = "blocked"
          enabled = "allowed"
        end


        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == disabled }

        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == enabled }

        true
      end

      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def enabled_least_restrictive?(policy_data, policy)
        # Copilot for Dotcom is actually a groupings of policies that includes PR Summarizations
        # so we will check that instead
        if policy == :copilot_for_dotcom
          policy = :pr_summarizations
        end

        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" && data[:type] == :business }

        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "enabled" }

        false
      end

      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def disabled_least_restrictive?(policy_data, policy)
        # Copilot for Dotcom is actually a groupings of policies that includes PR Summarizations
        # so we will check that instead
        if policy == :copilot_for_dotcom
          policy = :pr_summarizations
        end

        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" && data[:type] == :business }

        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == "enabled" }

        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" }

        true
      end

      sig do
        params(policy_data: CopilotAllPolicies, policy: Symbol)
          .returns(CopilotSeatBreakdown)
      end
      def policy_breakdown(policy_data, policy)
        enabled = []
        disabled = []
        unconfigured = []
        no_policy = []

        policy_data.each do |data|
          if data[:config][policy] == "enabled" || data[:config][policy] == "allowed"
            enabled << { type: data[:type], name: data[:name] }
          elsif data[:config][policy] == "disabled" || data[:config][policy] == "blocked"
            disabled << { type: data[:type], name: data[:name] }
          elsif data[:config][policy] == "no_policy"
            no_policy << { type: data[:type], name: data[:name] }
          elsif data[:config][policy] == "unconfigured"
            unconfigured << { type: data[:type], name: data[:name] }
          end
        end
        {
          enabled: enabled,
          disabled: disabled,
          unconfigured: unconfigured,
          no_policy: no_policy,
        }
      end

      sig { params(current_version: Integer).void }
      def create_copilot_settings_cache(current_version)
        copilot_user = copilot_user_object
        timestamp = Time.now.to_i
        version = current_version
        data = {}
        data[:version] = version
        data[:timestamp] = timestamp
        data[:settings] = {}
        data[:plan_details] = {}
        data[:copilot_settings] = {}
        data[:policy_breakdown] = {}

        access_type = copilot_user.access_type
        all_policies = copilot_user.all_policies

        # Add new policies here. The name is the key that will be stored in the user settings
        # the policy is the name of the policy we check when calling policy_enabled?

        if copilot_user.has_cfi_access?
          data[:settings][:organization_ids] = []
          data[:settings][:business_ids] = []
          data[:settings][:analytics_tracking_id] = user_object.analytics_tracking_id

          data[:plan_details][:has_cb_access] = false
          data[:plan_details][:has_ce_access] = false
          data[:plan_details][:has_ci_access] = true
          data[:plan_details][:has_trial_access] = copilot_user.has_trial_subscription?
          data[:plan_details][:has_free_pro_access] = copilot_user.has_free_access?
          data[:plan_details][:has_paid_access] = copilot_user.has_paid_access?
          data[:plan_details][:has_limited_access] = copilot_user.has_limited_access?
          data[:plan_details][:access_type] = access_type

          # These are special cases for CFI
          cfi_policies_to_remove = [
            :extensions_enabled,
            :cli_enabled,
            :private_docs_enabled,
            :mobile_chat_enabled,
            :o1_enabled,
            :o1_disable
          ]
          cfi_policies_to_remove << :bing_github_chat_enabled if !copilot_user.feature_enabled?(:copilot_dotcom_chat_bing_ci)

          cfi_policies = THE_POLICIES.reject { |pd| cfi_policies_to_remove.include? pd[:name] }
          cfi_policies.each do |p|
            data[:copilot_settings][p[:name]] = copilot_user.policy_enabled?(copilot_user, all_policies, p[:policy])
          end

          data[:copilot_settings][:a_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :a_chat)
          data[:copilot_settings][:g_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_chat)
          data[:copilot_settings][:o1_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o1)

          # Special cases for now
          data[:copilot_settings][:bing_github_chat_enabled] = false if !copilot_user.feature_enabled?(:copilot_dotcom_chat_bing_ci)
          data[:copilot_settings][:cli_enabled] = false
          data[:copilot_settings][:custom_models_enabled] = copilot_user.custom_models_enabled?
          data[:copilot_settings][:private_docs_enabled] = false
          data[:copilot_settings][:mobile_chat_enabled] = true
          data[:copilot_settings][:extensions_enabled] = copilot_user.copilot_extensions_enabled?
          data[:copilot_settings][:o1_enabled] = true
          data[:copilot_settings][:o1_disabled] = false
        elsif copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
          data[:settings][:organization_ids] = all_policies.filter { |pd| pd[:type] == :organization }.pluck(:id)
          data[:settings][:business_ids] = all_policies.filter { |pd| pd[:type] == :business }.pluck(:id)
          data[:settings][:analytics_tracking_id] = user_object.analytics_tracking_id

          data[:plan_details][:has_cb_access] = copilot_user.has_cfb_access?
          data[:plan_details][:has_ce_access] = copilot_user.has_cfe_access?
          data[:plan_details][:has_ci_access] = false
          data[:plan_details][:has_trial_access] = copilot_user.has_trial_subscription?
          data[:plan_details][:has_free_pro_access] = copilot_user.has_free_access?
          data[:plan_details][:has_paid_access] = copilot_user.has_paid_access?
          data[:plan_details][:access_type] = access_type
          data[:plan_details][:eligible_for_trial] = copilot_user.eligible_for_trial?
          data[:plan_details][:days_left_on_trial] = copilot_user.days_left_on_trial
          data[:plan_details][:has_subscription_ended] = copilot_user.has_subscription_ended?
          data[:plan_details][:is_technical_preview_user] = copilot_user.is_technical_preview_user?
          data[:plan_details][:technical_preview_user_lost_access] = copilot_user.technical_preview_user_lost_access?

          THE_POLICIES.each do |p|
            data[:copilot_settings][p[:name]] = copilot_user.policy_enabled?(copilot_user, all_policies, p[:policy])
          end

          data[:copilot_settings][:a_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :a_chat)
          data[:copilot_settings][:g_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_chat)
          data[:copilot_settings][:o1_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o1)

          # This is always a special case
          data[:copilot_settings][:custom_models_enabled] = copilot_user.custom_models_enabled? # This is not in consolidated policies due to the way it is calculated

          THE_POLICIES.each do |p|
            data[:policy_breakdown][p[:policy]] = copilot_user.policy_breakdown(all_policies, p[:policy])
          end

          # Special cases for now
          data[:policy_breakdown][:bing_github_chat] = copilot_user.policy_breakdown(all_policies, :bing_github_chat)
          data[:policy_breakdown][:cli] = copilot_user.policy_breakdown(all_policies, :cli)
          data[:policy_breakdown][:private_docs] = copilot_user.policy_breakdown(all_policies, :private_docs)
          data[:policy_breakdown][:mobile_chat] = copilot_user.policy_breakdown(all_policies, :mobile_chat)
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          user_object.settings.set!(:copilot_policy_data, data.to_json(fields:
            [:version, :timestamp, :settings, :plan_details, :copilot_settings, :policy_breakdown]
          ))
        end
      end
    end
  end
end
