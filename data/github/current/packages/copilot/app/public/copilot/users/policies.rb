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
          { name: :agent_mode_enabled, policy: :agent_mode },
          { name: :agent_mode_auto_approve_enabled, policy: :agent_mode_auto_approve },
          { name: :automatic_code_review_enabled, policy: :automatic_code_review },
          { name: :overages_enabled, policy: :overages },
          { name: :swe_agent_enabled, policy: :swe_agent },
          { name: :mcp_enabled, policy: :mcp },
          { name: :spark_enabled, policy: :spark },
          { name: :insights_enabled, policy: :insights },
          { name: :code_review_enabled, policy: :code_review },
          { name: :code_review_beta_features_enabled, policy: :code_review_beta_features },
          { name: :generated_commit_message_enabled, policy: :generated_commit_message },
      ], T::Array[{ name: Symbol, policy: Symbol }])

      THE_MODELS = T.let([
          { name: :afos_enabled, policy: :afos },
          { name: :antman_enabled, policy: :antman },
          { name: :aofo_enabled, policy: :aofo },
          { name: :arcticfox_enabled, policy: :arcticfox },
          { name: :bento_enabled, policy: :bento },
          { name: :blackpanther_enabled, policy: :blackpanther },
          { name: :blueberry_enabled, policy: :blueberry },
          { name: :captainamerica_enabled, policy: :captainamerica },
          { name: :cherry_enabled, policy: :cherry },
          { name: :cucumber_enabled, policy: :cucumber },
          { name: :g_tf_enabled, policy: :g_tf },
          { name: :grok_code_enabled, policy: :grok_code },
          { name: :gtff_enabled, policy: :gtff },
          { name: :hulk_enabled, policy: :hulk },
          { name: :lotus_enabled, policy: :lotus },
          { name: :m_ironman_enabled, policy: :m_ironman },
          { name: :m_spiderman_enabled, policy: :m_spiderman },
          { name: :m_thor_enabled, policy: :m_thor },
          { name: :o_ff_enabled, policy: :o_ff },
          { name: :o1_enabled, policy: :o1 },
          { name: :o3_enabled, policy: :o3 },
          { name: :obmb_enabled, policy: :obmb },
          { name: :obmw_enabled, policy: :obmw },
          { name: :ofct_enabled, policy: :ofct },
          { name: :ofo_enabled, policy: :ofo },
          { name: :sunflower_enabled, policy: :sunflower },
          { name: :tulip_enabled, policy: :tulip },
          { name: :watermelon_enabled, policy: :watermelon },
          { name: :wintersoldier_enabled, policy: :wintersoldier },
        ], T::Array[{ name: Symbol, policy: Symbol }])

      CopilotAllPolicies = T.type_alias do
        T::Array[
          T.any(
            { type: Symbol, name: String, id: Integer, config: T.nilable(Copilot::Configuration) },
            { type: Symbol, name: String, id: Integer, config: T.nilable(Copilot::Configuration), parent_id: T.nilable(Integer) },
          )
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
            business_id = policy_data[:organization].try(&:business)&.id
          end
          {
            type: type,
            name: name,
            config: config,
            id: id,
            parent_id: business_id,
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

        # if the user is unaffiliated, the current provider is business, and the policy is set to `no_policy`
        # we will check if the fallback policy is enabled for the user
        return true if business_copilot_provider_ea_user_fallback_policy_enabled?(policy)

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

      # Special case for handling agent mode
      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def enabled_least_restrictive_agent_mode?(policy_data, policy)
        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" && data[:type] == :business }

        # if there are any associated orgs that have the policy enabled, we will return true
        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "enabled" }

        # if the user is unaffiliated, the current provider is business, and the policy is set to `no_policy`
        # we will check if the fallback policy is enabled for the user
        return true if business_copilot_provider_ea_user_fallback_policy_enabled?(policy)

        true
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

        return false if business_copilot_provider_ea_user_fallback_policy_enabled?(policy)

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

      sig { params(policy_data: CopilotAllPolicies, policy: Symbol).returns(T::Boolean) }
      def disabled_least_restrictive_agent_mode?(policy_data, policy)
        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" && data[:type] == :business }

        return false if policy_data.any? { |data| data[:config] && data[:config][policy] == "enabled" }

        return true if policy_data.any? { |data| data[:config] && data[:config][policy] == "disabled" }

        return false if business_copilot_provider_ea_user_fallback_policy_enabled?(policy)

        false
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

      sig do
        params(policy_data: CopilotAllPolicies, model_key: String)
          .returns(CopilotSeatBreakdown)
      end
      def model_registry_breakdown(policy_data, model_key)
        enabled = []
        disabled = []
        unconfigured = []
        no_policy = []

        policy_data.each do |data|
          model_policy_value = data[:config]&.model_policy(model_key)
          if model_policy_value == "enabled"
            enabled << { type: data[:type], name: data[:name] }
          elsif model_policy_value == "disabled"
            disabled << { type: data[:type], name: data[:name] }
          elsif model_policy_value == "unconfigured"
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

      sig { params(current_version: Integer, throttle: T::Boolean, reason: T.nilable(String)).void }
      def create_copilot_settings_cache(current_version, throttle: false, reason: nil)
        dd_license_type = if copilot_user_object.has_cfi_access?
          "cfi"
        elsif copilot_user_object.has_cfb_access? || copilot_user_object.has_cfe_access?
          "cfb"
        else
          "no access"
        end
        GitHub.dogstats.distribution_time("copilot.settings_cache.update_time", tags: ["copilot_license:#{dd_license_type}"]) do
          GitHub.dogstats.increment(
            "copilot.settings_cache.updated",
            tags: ["creation_reason:#{reason || 'unknown'}", "copilot_license:#{dd_license_type}"],
          )

          # if we don't know the reason, log that and show the stack trace to help with debugging
          if reason.nil?
            GitHub.logger.info("Updating settings cache for unknown reason", {
              "gh.copilot.caller" => Kernel.caller.first(5).join(" | "),
            })
          end

          data = compute_copilot_settings_cache(current_version)

          write_was_successful = Copilot::UserCache.new(user: user_object).write(data, throttle: throttle)
          if write_was_successful
            GitHub.logger.info("Cached copilot settings for user", {
              "gh.user.id" => user_object.id,
              "gh.user.login" => user_object.display_login,
              "gh.copilot.policy_cache.version" => current_version,
            })
          end
        end
      end

      sig { params(current_version: Integer).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
      def compute_copilot_settings_cache(current_version)
        GitHub.dogstats.distribution_time("copilot.settings_cache.compute_time") do
          copilot_user = copilot_user_object
          timestamp = Time.now.to_i
          version = current_version
          data = {}
          data[:version] = version
          data[:timestamp] = timestamp
          data[:settings] = {}
          data[:plan_details] = {}
          data[:copilot_settings] = {}
          data[:copilot_policies] = {}
          data[:policy_breakdown] = {}

          access_type = copilot_user.access_type.to_s
          all_policies = copilot_user.all_policies

          # store both with and without trials so public user consumers have flexibility
          data[:plan_details][:serialized_plan] = copilot_user.copilot_plan_enum&.serialize
          data[:plan_details][:serialized_plan_no_trials] = copilot_user.copilot_plan_enum(include_trials: false)&.serialize

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
            data[:plan_details][:has_max_access] = copilot_user.has_max_access?
            data[:plan_details][:has_trial_access] = copilot_user.has_trial_subscription?
            data[:plan_details][:has_free_pro_access] = copilot_user.has_free_access?
            data[:plan_details][:has_educational_access] = copilot_user.has_educational_access?
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
              when :afos
                data[:copilot_settings][:afos_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :afos)
                data[:copilot_settings][:afos_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :afos)
              when :g_tf
                data[:copilot_settings][:g_tf_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :g_tf)
                data[:copilot_settings][:g_tf_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_tf)
              when :gtff
                data[:copilot_settings][:gtff_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :gtff)
                data[:copilot_settings][:gtff_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :gtff)
              when :o_ff
                data[:copilot_settings][:o_ff_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :o_ff)
                data[:copilot_settings][:o_ff_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o_ff)
              when :ofct
                data[:copilot_settings][:ofct_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :ofct)
                data[:copilot_settings][:ofct_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :ofct)
              when :obmb
                data[:copilot_settings][:obmb_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :obmb)
                data[:copilot_settings][:obmb_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :obmb)
              when :obmw
                data[:copilot_settings][:obmw_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :obmw)
                data[:copilot_settings][:obmw_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :obmw)
              when :aofo
                data[:copilot_settings][:aofo_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :aofo)
                data[:copilot_settings][:aofo_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :aofo)
              when :ofo
                data[:copilot_settings][:ofo_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :ofo)
                data[:copilot_settings][:ofo_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :ofo)
              when :grok_code
                data[:copilot_settings][:grok_code_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :grok_code)
                data[:copilot_settings][:grok_code_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :grok_code)
              when :m_ironman
                data[:copilot_settings][:m_ironman_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :m_ironman)
                data[:copilot_settings][:m_ironman_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :m_ironman)
              when :m_spiderman
                data[:copilot_settings][:m_spiderman_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :m_spiderman)
                data[:copilot_settings][:m_spiderman_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :m_spiderman)
              when :m_thor
                data[:copilot_settings][:m_thor_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :m_thor)
                data[:copilot_settings][:m_thor_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :m_thor)
              when :antman
                data[:copilot_settings][:antman_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :antman)
                data[:copilot_settings][:antman_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :antman)
              when :hulk
                data[:copilot_settings][:hulk_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :hulk)
                data[:copilot_settings][:hulk_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :hulk)
              when :blackpanther
                data[:copilot_settings][:blackpanther_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :blackpanther)
                data[:copilot_settings][:blackpanther_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :blackpanther)
              when :captainamerica
                data[:copilot_settings][:captainamerica_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :captainamerica)
                data[:copilot_settings][:captainamerica_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :captainamerica)
              when :wintersoldier
                data[:copilot_settings][:wintersoldier_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :wintersoldier)
                data[:copilot_settings][:wintersoldier_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :wintersoldier)
              else
                data[:copilot_settings][m[:name]] = Copilot::Users::ModelAccess.model_available?(copilot_user, m[:policy])
                disabled_name = m[:name].to_s.sub(/_enabled$/, "_disabled")
                data[:copilot_settings][disabled_name.to_sym] = Copilot::Users::ModelAccess.model_unavailable?(copilot_user, m[:policy])
              end
            end

            data[:copilot_settings][:editor_preview_features_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :editor_preview_features)
            data[:copilot_settings][:agent_mode_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :agent_mode)
            data[:copilot_settings][:agent_mode_auto_approve_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :agent_mode_auto_approve)


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
            data[:plan_details][:has_educational_access] = copilot_user.has_educational_access?
            data[:plan_details][:has_paid_access] = copilot_user.has_paid_access?
            data[:plan_details][:access_type] = access_type
            data[:plan_details][:has_subscription_ended] = copilot_user.has_subscription_ended?
            data[:plan_details][:is_technical_preview_user] = copilot_user.is_technical_preview_user?
            data[:plan_details][:technical_preview_user_lost_access] = copilot_user.technical_preview_user_lost_access?

            [*THE_POLICIES, *THE_MODELS].each do |p|
              data[:copilot_settings][p[:name]] = copilot_user.policy_enabled?(copilot_user, all_policies, p[:policy])
            end

            data[:copilot_settings][:automatic_code_review_enabled] = copilot_user.automatic_code_review_enabled?
            data[:copilot_settings][:automatic_code_review_disabled] = copilot_user.automatic_code_review_disabled?

            data[:copilot_settings][:editor_preview_features_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :editor_preview_features)
            data[:copilot_settings][:agent_mode_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :agent_mode)
            data[:copilot_settings][:agent_mode_auto_approve_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :agent_mode_auto_approve)
            data[:copilot_settings][:afos_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :afos)
            data[:copilot_settings][:g_tf_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :g_tf)
            data[:copilot_settings][:gtff_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :gtff)
            data[:copilot_settings][:o1_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o1)
            data[:copilot_settings][:o3_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :o3)
            data[:copilot_settings][:ofct_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :ofct)
            data[:copilot_settings][:obmb_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :obmb)
            data[:copilot_settings][:obmw_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :obmw)
            data[:copilot_settings][:aofo_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :aofo)
            data[:copilot_settings][:ofo_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :ofo)
            data[:copilot_settings][:grok_code_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :grok_code)
            data[:copilot_settings][:m_ironman_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :m_ironman)
            data[:copilot_settings][:m_spiderman_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :m_spiderman)
            data[:copilot_settings][:m_thor_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :m_thor)

            # This is always a special case
            data[:copilot_settings][:custom_models_enabled] = copilot_user.custom_models_enabled? # This is not in consolidated policies due to the way it is calculated

            Copilot::Policies::ALL.each do |policy_class|
              data[:policy_breakdown][policy_class.config_name.to_sym] = copilot_user.policy_breakdown(all_policies, policy_class.config_name.to_sym)
            end

            # overages are not tracked in the policy class system
            data[:policy_breakdown][:overages] = copilot_user.policy_breakdown(all_policies, :overages)
          end

          # Set defaults for the swe_agent policy
          data[:copilot_settings][:swe_agent_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :swe_agent)
          data[:copilot_settings][:swe_agent_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :swe_agent)

          # Policies to cache for all users...
          data[:plan_details][:can_signup_for_free] = copilot_user.can_signup_for_free?
          data[:plan_details][:can_signup_for_educational] = copilot_user.can_signup_for_educational?
          data[:plan_details][:eligible_for_trial] = copilot_user.eligible_for_trial?
          data[:plan_details][:days_left_on_trial] = copilot_user.days_left_on_trial

          # Set defaults for the mcp policy
          data[:copilot_settings][:mcp_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :mcp)
          data[:copilot_settings][:mcp_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :mcp)

          # Set defaults for the Spark policy
          data[:copilot_settings][:spark_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :spark)
          data[:copilot_settings][:spark_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :spark)

          # Set defaults for the insights policy
          data[:copilot_settings][:insights_enabled] = copilot_user.policy_enabled?(copilot_user, all_policies, :insights)
          data[:copilot_settings][:insights_disabled] = copilot_user.policy_disabled?(copilot_user, all_policies, :insights)

          # use the value unless the policy is not available. in that case it should be 'invalid'
          Copilot::Policies::CACHEABLE.each do |policy_class|
            if copilot_user.feature_flag_enabled?(:copilot_check_availability_in_twirp, default: false) || policy_class.available_for?(copilot_user)
              data[:copilot_policies][policy_class.config_name.to_sym] = policy_class.effective_value(copilot_user, all_policies)
            else
              data[:copilot_policies][policy_class.config_name.to_sym] = "invalid"
            end
          end

          # Cache model registry policies
          # Skip entire model_registry block for CI users with bypass — they compute
          # model access directly from the registry in twirp_user_settings
          skip_model_registry_cache = copilot_user.feature_flag_enabled?(:copilot_ci_model_registry_bypass, default: false) && copilot_user.has_cfi_access? && !copilot_user.has_cfb_access? && !copilot_user.has_cfe_access?
          unless skip_model_registry_cache
            data[:model_registry] = {}
            available_models = Copilot::ModelsRegistryCache.for_user(copilot_user)
            data[:model_registry][:model_policies] = {}
            data[:model_registry][:policy_breakdown] = {}
            data[:model_registry][:models_last_checked_at] = Time.now.utc.iso8601

            # Store feature flag states and registry snapshot for efficient staleness detection
            # This allows us to detect when a user's model access changes without calling for_user
            all_models = Copilot::ModelsRegistryCache.all_cached

            data[:model_registry][:ff_snapshot] = {
              internal_models: copilot_user.feature_flag_enabled?(:copilot_registry_internal_models_testing, default: false),
              # Store state for each model-specific feature flag
              model_flags: all_models
                .filter { |m| m.feature_flag.present? }
                .map { |m| [m.feature_flag, copilot_user.feature_flag_enabled?(m.feature_flag.to_sym, default: false)] }
                .to_h,
              # Store hash of all models in registry to detect when models are added/removed
              registry_hash: Digest::SHA256.hexdigest(all_models.map(&:model_key).sort.join(",")),
              # Store hash of models user actually has access to - this captures plan changes
              # since plan changes affect which models are available
              user_models_hash: Digest::SHA256.hexdigest(available_models.map(&:model_key).sort.join(","))
            }

            available_models.each do |model|
              data[:model_registry][:model_policies][model.model_key] = copilot_user.model_policy(model.model_key)
              data[:model_registry][:policy_breakdown][model.model_key] = copilot_user.model_registry_breakdown(all_policies, model.model_key)
            end
          end

          [data[:policy_breakdown], data.dig(:model_registry, :policy_breakdown)].compact.each do |breakdown|
            breakdown.deep_transform_values! { |value| value.to_s }
          end

          data
        end
      end

      sig { returns(T::Boolean) }
      memoize def is_enterprise_assigned_user?
        return false unless copilot_businesses.any?

        copilot_obj = copilot_seat_provider&.__getobj__
        return false unless copilot_obj.is_a?(::Business) && !copilot_seat_provider&.copilot_standalone?

        return false unless copilot_obj.unaffiliated_member?(self)

        true
      end

      # If the user has an enterprise-assigned Copilot seat (unaffiliated user) we check if the policy is set to `no_policy` and if so
      # determine if this policy is enabled for the user based on the fallback policy setting.
      sig { params(policy: Symbol).returns(T::Boolean) }
      def business_copilot_provider_ea_user_fallback_policy_enabled?(policy)
        return false unless copilot_businesses.any?

        copilot_obj = copilot_seat_provider&.__getobj__
        return false unless copilot_obj.is_a?(::Business) && !copilot_seat_provider&.copilot_standalone?

        return false unless copilot_obj.unaffiliated_member?(self)

        provider = T.cast(copilot_seat_provider, Copilot::Business)
        return true if T.unsafe(provider)&.send(policy) == "no_policy" && provider.ea_user_fallback_policy_enabled?

        false
      end

      # This is effectively a reimplementation of Copilot::Users::Access#copilot_provider so we don't get into
      # a circular dependency when called in business_copilot_provider_ea_user_fallback_policy_enabled?
      sig { returns(T.nilable(T.any(Copilot::Organization, Copilot::Business))) }
      memoize def copilot_seat_provider
        if copilot_user_object.has_copilot_standalone_business?
          return T.must(copilot_user_object.copilot_standalone_businesses&.first)
        end
        copilot_org = copilot_user_object.copilot_organizations.find do |co|
          co.copilot_plan == copilot_user_object.copilot_plan
        end

        return copilot_org if copilot_org

        if copilot_user_object.has_copilot_access_through_business?
          T.must(copilot_user_object.copilot_businesses_including_unaffiliated_and_outside_collaborators.first)
        else
          nil
        end
      end
    end
  end
end
