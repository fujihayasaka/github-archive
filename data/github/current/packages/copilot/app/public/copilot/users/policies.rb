
# typed: strict
# frozen_string_literal: true

# THIS IS A WORK IN PROGRESS. PLEASE DO NOT USE THIS FILE AS A REFERENCE FOR ANYTHING UNLESS YOU ARE WORKING ON THIS FEATURE.
# YOU CAN USE THIS ONCE THIS COMMENT IS UPDATED

module Copilot
  module Users
    module Policies
      extend T::Helpers
      extend T::Sig

      include Copilot::Users::Signatures
      include GitHub::Memoizer

      # Add new policies here. The name is the key that will be stored in the user settings
      # the policy is the name of the policy we check when calling policy_enabled?
      THE_POLICIES = T.let([
          { name: :dotcom_chat_enabled, policy: :dotcom_chat },
          { name: :pr_summarizations_enabled, policy: :pr_summarizations },
          { name: :public_code_suggestions_enabled, policy: :public_code_suggestions },
          { name: :mobile_chat_enabled, policy: :mobile_chat },
          { name: :extensions_enabled, policy: :copilot_extensions },
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
      memoize def all_policies # rubocop:disable Naming/MemoizedInstanceVariableName
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

      sig { returns CopilotAllPolicies }
      def fresh_policies # rubocop:disable Naming/MemoizedInstanceVariableName
        collated_data = copilot_user_object.async_collated_copilot_for_business_configurations(false).sync
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
        all_policies = copilot_user.fresh_policies

        # Add new policies here. The name is the key that will be stored in the user settings
        # the policy is the name of the policy we check when calling policy_enabled?

        if copilot_user.has_cfi_access?
          data[:settings][:copilot_organizations] = []
          data[:settings][:copilot_businesses] = []
          data[:settings][:analytics_tracking_id] = user_object.analytics_tracking_id

          data[:plan_details][:has_cb_access] = false
          data[:plan_details][:has_ce_access] = false
          data[:plan_details][:has_ci_access] = true
          data[:plan_details][:has_free_access] = copilot_user.has_free_access?
          data[:plan_details][:has_paid_access] = copilot_user.has_paid_access?
          data[:plan_details][:access_type] = access_type

          THE_POLICIES.each do |p|
            data[:copilot_settings][p[:name]] = copilot_user.policy_enabled?(copilot_user, all_policies, p[:policy])
          end

          # Special cases for now
          data[:copilot_settings][:bing_github_chat_enabled] = false
          data[:copilot_settings][:cli_enabled] = false
          data[:copilot_settings][:custom_models_enabled] = copilot_user.custom_models_enabled?
          data[:copilot_settings][:private_docs_enabled] = false
        elsif copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
          data[:settings][:copilot_organizations] = all_policies.filter { |pd| pd[:type] == :organization }.pluck(:id)
          data[:settings][:copilot_businesses] = all_policies.filter { |pd| pd[:type] == :business }.pluck(:id)
          data[:settings][:analytics_tracking_id] = user_object.analytics_tracking_id

          data[:plan_details][:has_cb_access] = copilot_user.has_cfb_access?
          data[:plan_details][:has_ce_access] = copilot_user.has_cfe_access?
          data[:plan_details][:has_ci_access] = false
          data[:plan_details][:has_free_access] = copilot_user.has_free_access?
          data[:plan_details][:has_paid_access] = copilot_user.has_paid_access?
          data[:plan_details][:access_type] = access_type

          THE_POLICIES.each do |p|
            data[:copilot_settings][p[:name]] = copilot_user.policy_enabled?(copilot_user, all_policies, p[:policy])
          end

          # Special cases for now
          data[:copilot_settings][:bing_github_chat_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :bing_github_chat)
          data[:copilot_settings][:cli_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :cli)
          data[:copilot_settings][:custom_models_enabled] = copilot_user.custom_models_enabled? # This is not in consolidated policies due to the way it is calculated
          data[:copilot_settings][:private_docs_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :private_docs)

          THE_POLICIES.each do |p|
            data[:policy_breakdown][p[:policy]] = copilot_user.policy_breakdown(all_policies, p[:policy])
          end

          # Special cases for now
          data[:policy_breakdown][:bing_github_chat] = copilot_user.policy_breakdown(all_policies, :bing_github_chat)
          data[:policy_breakdown][:cli] = copilot_user.policy_breakdown(all_policies, :cli)
          data[:policy_breakdown][:private_docs] = copilot_user.policy_breakdown(all_policies, :private_docs)
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
