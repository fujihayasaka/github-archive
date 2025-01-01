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
          { name: :desktop_enabled, policy: :desktop },
          { name: :private_docs_enabled, policy: :private_docs },
          { name: :mobile_chat_enabled, policy: :mobile_chat },
          { name: :user_feedback_opt_in_enabled, policy: :user_feedback_opt_in },
          { name: :beta_features_github_chat_enabled, policy: :beta_features_github_chat },
          { name: :editor_preview_features_enabled, policy: :editor_preview_features },
          { name: :automatic_code_review_enabled, policy: :automatic_code_review },
          { name: :overages_enabled, policy: :overages },
          { name: :swe_agent_enabled, policy: :swe_agent },
          { name: :mcp_enabled, policy: :mcp },
      ], T::Array[{ name: Symbol, policy: Symbol }])

      THE_MODELS = T.let([
          { name: :a_chat_enabled, policy: :a_chat },
          { name: :a_f_enabled, policy: :a_f },
          { name: :afos_enabled, policy: :afos },
          { name: :al_enabled, policy: :al },
          { name: :g_chat_enabled, policy: :g_chat },
          { name: :g_tf_enabled, policy: :g_tf },
          { name: :gtff_enabled, policy: :gtff },
          { name: :o1_enabled, policy: :o1 },
          { name: :o3_enabled, policy: :o3 },
          { name: :o_ff_enabled, policy: :o_ff },
          { name: :o_fm_enabled, policy: :o_fm },
          { name: :o_f_enabled, policy: :o_f },
          { name: :o_t_enabled, policy: :o_t },
          { name: :ofo_enabled, policy: :ofo },
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

        # if there are any associated business that have the policy disabled, we will return false
        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" && data[:type] == :business }

        # if there are any associated orgs that have the policy enabled, we will return true
        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "enabled" }

        false
      end


      # Special case for handling models that are only for CFE
      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def enabled_least_restrictive_cfe?(policy_data, policy)
        # Copilot for Dotcom is actually a groupings of policies that includes PR Summarizations
        # so we will check that instead
        if policy == :copilot_for_dotcom
          policy = :pr_summarizations
        end

        # if there are any associated business that have the policy disabled, we will return false
        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" && data[:type] == :business }

        # if there are any associated CFE orgs that have the policy enabled, we will return true
        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "enabled" && data[:type] == :organization && data[:config][:copilot_plan] == "enterprise" }

        false
      end

      # In a small number of cases, we want to check if a policy is truly disabled.
      # This will ignore cases where an enterprise has the policy disabled.
      # You almost certainly don't want to do this.
      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def enabled_true_least_restrictive?(policy_data, policy)
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

      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def disabled_least_restrictive_cfe?(policy_data, policy)
        # Copilot for Dotcom is actually a groupings of policies that includes PR Summarizations
        # so we will check that instead
        if policy == :copilot_for_dotcom
          policy = :pr_summarizations
        end

        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" && data[:type] == :business }

        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == "enabled" && data[:type] == :organization && data[:config][:copilot_plan] == "enterprise" }

        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" }

        true
      end

      # In a small number of cases, we want to check if a policy is truly disabled.
      # This will ignore cases where an enterprise has the policy disabled.
      # You almost certainly don't want to do this.
      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def disabled_true_least_restrictive?(policy_data, policy)
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
          data[:plan_details][:has_pro_plus_access] = copilot_user.has_pro_plus_access?
          data[:plan_details][:has_pro_access] = copilot_user.has_pro_access?
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
            :desktop_enabled,
          ]

          cfi_policies = THE_POLICIES.reject { |pd| cfi_policies_to_remove.include? pd[:name] }
          cfi_policies.each do |p|
            data[:copilot_settings][p[:name]] = copilot_user.policy_enabled?(copilot_user, all_policies, p[:policy])
          end

          # MODELS
          THE_MODELS.each do |m|
            case m[:policy]
            when :a_f
              data[:copilot_settings][:a_f_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :a_f)
              data[:copilot_settings][:a_f_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :a_f)
            when :afos
              data[:copilot_settings][:afos_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :afos)
              data[:copilot_settings][:afos_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :afos)
            when :al
              data[:copilot_settings][:al_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :al)
              data[:copilot_settings][:al_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :al)
            when :a_chat
              data[:copilot_settings][:a_chat_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :a_chat)
              data[:copilot_settings][:a_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :a_chat)
            when :g_chat
              data[:copilot_settings][:g_chat_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :g_chat)
              data[:copilot_settings][:g_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_chat)
            when :g_tf
              data[:copilot_settings][:g_tf_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :g_tf)
              data[:copilot_settings][:g_tf_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_tf)
            when :gtff
              data[:copilot_settings][:gtff_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :gtff)
              data[:copilot_settings][:gtff_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :gtff)
            when :o_ff
              data[:copilot_settings][:o_ff_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :o_ff)
              data[:copilot_settings][:o_ff_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o_ff)
            when :o_fm
              data[:copilot_settings][:o_fm_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :o_fm)
              data[:copilot_settings][:o_fm_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o_fm)
            when :o_t
              data[:copilot_settings][:o_t_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :o_t)
              data[:copilot_settings][:o_t_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o_t)
            when :ofo
              data[:copilot_settings][:ofo_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :ofo)
              data[:copilot_settings][:ofo_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :ofo)
            else
              data[:copilot_settings][m[:name]] = Copilot::Users::ModelAccess.model_available?(copilot_user, m[:policy])
              disabled_name = m[:name].to_s.sub(/_enabled$/, "_disabled")
              data[:copilot_settings][disabled_name.to_sym] = Copilot::Users::ModelAccess.model_unavailable?(copilot_user, m[:policy])
            end
          end

          data[:copilot_settings][:editor_preview_features_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :editor_preview_features)


          # Special cases for now
          data[:copilot_settings][:automatic_code_review_enabled] = copilot_user.automatic_code_review_enabled?
          data[:copilot_settings][:cli_enabled] = false
          data[:copilot_settings][:desktop_enabled] = copilot_user.desktop_enabled?
          data[:copilot_settings][:custom_models_enabled] = copilot_user.custom_models_enabled?
          data[:copilot_settings][:private_docs_enabled] = false
          data[:copilot_settings][:mobile_chat_enabled] = true
          data[:copilot_settings][:extensions_enabled] = copilot_user.copilot_extensions_enabled?
        elsif copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
          data[:settings][:organization_ids] = all_policies.filter { |pd| pd[:type] == :organization }.pluck(:id)
          data[:settings][:business_ids] = all_policies.filter { |pd| pd[:type] == :business }.pluck(:id)
          data[:settings][:analytics_tracking_id] = user_object.analytics_tracking_id

          data[:plan_details][:has_cb_access] = copilot_user.has_cfb_access?
          data[:plan_details][:has_ce_access] = copilot_user.has_cfe_access?
          data[:plan_details][:has_ci_access] = false
          data[:plan_details][:has_pro_plus_access] = false
          data[:plan_details][:has_pro_access] = false
          data[:plan_details][:has_trial_access] = copilot_user.has_trial_subscription?
          data[:plan_details][:has_free_pro_access] = copilot_user.has_free_access?
          data[:plan_details][:has_paid_access] = copilot_user.has_paid_access?
          data[:plan_details][:access_type] = access_type
          data[:plan_details][:eligible_for_trial] = copilot_user.eligible_for_trial?
          data[:plan_details][:days_left_on_trial] = copilot_user.days_left_on_trial
          data[:plan_details][:has_subscription_ended] = copilot_user.has_subscription_ended?
          data[:plan_details][:is_technical_preview_user] = copilot_user.is_technical_preview_user?
          data[:plan_details][:technical_preview_user_lost_access] = copilot_user.technical_preview_user_lost_access?

          [*THE_POLICIES, *THE_MODELS].each do |p|
            data[:copilot_settings][p[:name]] = copilot_user.policy_enabled?(copilot_user, all_policies, p[:policy])
          end

          data[:copilot_settings][:automatic_code_review_enabled] = copilot_user.automatic_code_review_enabled?
          data[:copilot_settings][:automatic_code_review_disabled] = copilot_user.automatic_code_review_disabled?

          data[:copilot_settings][:editor_preview_features_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :editor_preview_features)
          data[:copilot_settings][:a_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :a_chat)
          data[:copilot_settings][:a_f_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :a_f)
          data[:copilot_settings][:afos_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :afos)
          data[:copilot_settings][:al_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :al)
          data[:copilot_settings][:g_chat_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_chat)
          data[:copilot_settings][:g_tf_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_tf)
          data[:copilot_settings][:gtff_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :gtff)
          data[:copilot_settings][:o1_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o1)
          data[:copilot_settings][:o3_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o3)
          data[:copilot_settings][:o_fm_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o_fm)
          data[:copilot_settings][:o_t_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o_t)
          data[:copilot_settings][:ofo_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :ofo)

          # This is always a special case
          data[:copilot_settings][:custom_models_enabled] = copilot_user.custom_models_enabled? # This is not in consolidated policies due to the way it is calculated

          [*THE_POLICIES, *THE_MODELS].each do |p|
            data[:policy_breakdown][p[:policy]] = copilot_user.policy_breakdown(all_policies, p[:policy])
          end

          # Special cases for now
          data[:policy_breakdown][:bing_github_chat] = copilot_user.policy_breakdown(all_policies, :bing_github_chat)
          data[:policy_breakdown][:cli] = copilot_user.policy_breakdown(all_policies, :cli)
          data[:policy_breakdown][:private_docs] = copilot_user.policy_breakdown(all_policies, :private_docs)
          data[:policy_breakdown][:mobile_chat] = copilot_user.policy_breakdown(all_policies, :mobile_chat)
        end

        # Set defaults for the swe_agent policy
        data[:copilot_settings][:swe_agent_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :swe_agent)
        data[:copilot_settings][:swe_agent_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :swe_agent)

        # Policies to cache for all users...
        data[:plan_details][:can_signup_for_free] = copilot_user.can_signup_for_free?

        # Set defaults for the mcp policy
        data[:copilot_settings][:mcp_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :mcp)
        data[:copilot_settings][:mcp_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :mcp)

        ActiveRecord::Base.connected_to(role: :writing) do
          user_object.settings.set!(:copilot_policy_data, data.to_json(fields:
            [:version, :timestamp, :settings, :plan_details, :copilot_settings, :policy_breakdown]
          ))
        end
      end
    end
  end
end
