# typed: strict
# frozen_string_literal: true

module Copilot
  module Public
    class User
      include T::Helpers
      include GitHub::Memoizer
      include GitHub::ResilienceMixin
      include Scientist

      cattr_accessor :build_cache_on_initialize, default: !GitHub::AppEnvironment.test?

      # About versioning:
      # CURRENT_VERSION is the version of the cache that is being written to User.settings.
      # MINIMUM_VERSION is the minimum version of the cache that is acceptable to use as valid
      # data. If the cache is older than the minimum version, it will be reloaded. We might not need
      # these to always be in sync as features are developed to reduce the amount of reloading of data
      # for all users.
      CURRENT_VERSION = 26
      MINIMUM_VERSION = 26

      # Base time before a staleness check can trigger a cache rebuild.
      # Combined with per-user jitter (0 to staleness_jitter_range), the actual delay
      # is between staleness_rate_limit and staleness_rate_limit + staleness_jitter_range.
      sig { params(user: ::User).returns(ActiveSupport::Duration) }
      def self.staleness_rate_limit(user)
        if user.feature_flag_enabled?(:copilot_short_staleness_rate_limit, default: false) &&
            !user.feature_flag_enabled?(:copilot_long_staleness_rate_limit, default: false)
          15.minutes
        else
          30.minutes
        end
      end

      # Maximum jitter added on top of staleness_rate_limit.
      # Long mode uses a wider jitter (90 min) to spread checks over a 30–120 min window.
      sig { params(user: ::User).returns(ActiveSupport::Duration) }
      def self.staleness_jitter_range(user)
        if user.feature_flag_enabled?(:copilot_long_staleness_rate_limit, default: false)
          90.minutes
        else
          staleness_rate_limit(user)
        end
      end

      class Current < ActiveSupport::CurrentAttributes
        attribute :instances, default: {}
      end
      private_constant :Current

      sig { params(user: ::User).returns(Copilot::Public::User) }
      def self.for(user)
        cache_key = request_cache_key(user)
        instances = T.cast(Current.instances, T::Hash[String, Copilot::Public::User])
        instances[cache_key] ||= new(user)
      end

      sig { params(user: ::User).returns(String) }
      def self.request_cache_key(user)
        if user.id
          "user_id:#{user.id}"
        else
          "object_id:#{user.object_id}"
        end
      # Sorbet sig violations are Failbot-reported (not raised) in production, so `nil` or a
      # `SimpleDelegator` (e.g. `Copilot::User`) wrapping `nil` can reach here during upstream
      # degradation. Fall back to an object-id key.
      rescue NoMethodError => e
        Failbot.report(e,
          "code.namespace": "Copilot::Public::User",
          "code.function": "request_cache_key",
          "user.class": user.class.name,
        )
        "object_id:#{user.object_id}"
      end
      private_class_method :request_cache_key

      sig { returns(::User) }
      attr_reader :user

      sig { returns(ActiveSupport::Duration) }
      memoize def cache_refresh_interval
        Copilot::CacheRefreshIntervalSetting.current_interval
      end

      sig { returns(T.nilable(::String)) }
      memoize def analytics_tracking_id
        @analytics_tracking_id
      end

      sig { returns(T.nilable(Integer)) }
      memoize def user_id
        @user_id
      end

      alias id user_id

      sig { returns(T::Array[Integer]) }
      memoize def organization_ids
        @internal.dig(:settings, :organization_ids) || []
      end

      sig { returns(T::Array[Integer]) }
      memoize def business_ids
        @internal.dig(:settings, :business_ids) || []
      end

      sig { returns(T::Array[::Copilot::Organization]) }
      memoize def copilot_organizations
        return [] if @copilot_user.all_assignments_revoked?

        ::Organization.where(id: organization_ids).map do |organization|
          Copilot::Organization.new(organization)
        end
      end

      sig { returns(T::Array[Copilot::Business]) }
      memoize def copilot_businesses
        return [] if business_ids.empty?
        return [] if @copilot_user.all_assignments_revoked?

        ::Business.where(id: business_ids).map do |business|
          Copilot::Business.new(business)
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_cb_access?
        @internal.dig(:plan_details, :has_cb_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_ce_access?
        @internal.dig(:plan_details, :has_ce_access) || false
      end

      sig { params(include_trials: T::Boolean).returns(T.nilable(Copilot::Plan)) }
      def copilot_plan_enum(include_trials: true)
        plan = if include_trials
          @internal.dig(:plan_details, :serialized_plan)
        else
          @internal.dig(:plan_details, :serialized_plan_no_trials)
        end

        Copilot::Plans::CFI.try_deserialize(plan) || Copilot::Plans::CFB.try_deserialize(plan)
      end

      sig { returns(T::Boolean) }
      def has_enterprise_seat?
        has_ce_access? || has_cb_access?
      end

      sig { returns(T::Boolean) }
      memoize def is_enterprise_managed?
        user.is_enterprise_managed?
      end

      sig { returns(T::Boolean) }
      memoize def has_ci_access?
        @internal.dig(:plan_details, :has_ci_access) || false
      end

      sig { returns(String) }
      memoize def copilot_plan_from_cache
        # Calling @copilot_user.copilot_plan causes DB trilogy timeouts, so lets just use the cached values
        # TODO: switch over to using this method over copilot_plan, once we are feeling confident about it.
        return "enterprise" if has_ce_access?
        return "business" if has_cb_access?
        "individual"
      end

      # Free access in the context is actually Copilot Pro free access
      # Ex: OSS, Education, etc. users have free access to Copilot Pro
      # This is different from the free access that is available to all users
      sig { returns(T::Boolean) }
      memoize def has_free_pro_access?
        @internal.dig(:plan_details, :has_free_pro_access) || false
      end

      # this may or may not be different from free_pro_access, but we want to identify educational
      # users specifically
      sig { returns(T::Boolean) }
      memoize def has_educational_access?
        @internal.dig(:plan_details, :has_educational_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def can_signup_for_educational?
        @internal.dig(:plan_details, :can_signup_for_educational) || false
      end

      sig { returns(T::Boolean) }
      memoize def can_signup_for_free?
        @internal.dig(:plan_details, :can_signup_for_free) || false
      end

      sig { returns(T::Boolean) }
      memoize def can_modify_copilot_settings?
        organization_ids.empty? && has_copilot_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_paid_access?
        @internal.dig(:plan_details, :has_paid_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_paid_ci_access?
        has_ci_access? && has_paid_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_trial_access?
        @internal.dig(:plan_details, :has_trial_access) || false
      end

      # This is the Copilot Free plan that is available to all users
      sig  { returns(T::Boolean) }
      memoize def has_limited_access?
        @internal.dig(:plan_details, :has_limited_access) || false
      end

      # This is the Copilot Free plan that is available to OSS maintainers
      sig  { returns(T::Boolean) }
      memoize def has_free_access?
        @internal.dig(:plan_details, :has_free_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_individual_free_access?
        has_limited_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_individual_pro_access?
        has_ci_access? && !has_limited_access? && !has_max_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_individual_max_access?
        has_ci_access? && !has_limited_access? && has_max_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_access?
        has_paid_access? || has_free_pro_access? || has_trial_access? || has_limited_access? || has_cb_access? || has_ce_access? || has_educational_access?
      end

      sig { returns(Symbol) }
      memoize def access_type
        @internal.dig(:plan_details, :access_type)&.to_sym || :NO_ACCESS
      end

      sig { returns(T::Boolean) }
      memoize def has_pro_access?
        @internal.dig(:plan_details, :has_pro_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_pro_plus_access?
        @internal.dig(:plan_details, :has_pro_plus_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_max_access?
        @internal.dig(:plan_details, :has_max_access) || false
      end

      sig { params(key: Symbol).returns(String) }
      def policy_value(key)
        policy_values.dig(key) || "invalid"
      end

      sig { returns(T::Boolean) }
      memoize def public_code_suggestions_enabled?
        @internal.dig(:copilot_settings, :public_code_suggestions_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def ide_chat_enabled?
        @internal.dig(:copilot_settings, :chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def bing_github_chat_enabled?
        @internal.dig(:copilot_settings, :bing_github_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def editor_preview_features_enabled?
        @internal.dig(:copilot_settings, :editor_preview_features_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def editor_preview_features_disabled?
        @internal.dig(:copilot_settings, :editor_preview_features_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def agent_mode_enabled?
        return false if @copilot_user.user_object.feature_flag_enabled_or_raise?(:agent_mode_policy_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return true if @copilot_user.user_object.feature_flag_enabled_or_raise?(:agent_mode_policy_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        !agent_mode_disabled?
      end

      sig { returns(T::Boolean) }
      memoize def agent_mode_disabled?
        return true if @copilot_user.user_object.feature_flag_enabled_or_raise?(:agent_mode_policy_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if @copilot_user.user_object.feature_flag_enabled_or_raise?(:agent_mode_policy_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @internal.dig(:copilot_settings, :agent_mode_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def automatic_code_review_enabled?
        @internal.dig(:copilot_settings, :automatic_code_review_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def automatic_code_review_disabled?
        @internal.dig(:copilot_settings, :automatic_code_review_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def afos_enabled?
        return false if has_limited_access?
        @internal.dig(:copilot_settings, :afos_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def afos_disabled?
        return true if has_limited_access?
        @internal.dig(:copilot_settings, :afos_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def aofo_enabled?
        return false if !has_premium_access?
        @internal.dig(:copilot_settings, :aofo_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def aofo_disabled?
        return true if !has_premium_access?
        @internal.dig(:copilot_settings, :aofo_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def g_tf_enabled?
        return false if has_limited_access?

        @internal.dig(:copilot_settings, :g_tf_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def g_tf_disabled?
        return true if has_limited_access?

        @internal.dig(:copilot_settings, :g_tf_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def gtff_enabled?
        return false if !user_object.feature_flag_enabled_or_raise?(:copilot_gtff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @internal.dig(:copilot_settings, :gtff_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def gtff_disabled?
        return true if !user_object.feature_flag_enabled_or_raise?(:copilot_gtff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @internal.dig(:copilot_settings, :gtff_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o1_enabled?
        return false if has_limited_access?
        return true if has_ci_access?
        @internal.dig(:copilot_settings, :o1_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o1_disabled?
        return true if has_limited_access?
        return false if has_ci_access?
        @internal.dig(:copilot_settings, :o1_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o3_enabled?
        return true if has_limited_access?
        return true if has_ci_access?
        @internal.dig(:copilot_settings, :o3_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o3_disabled?
        return false if has_limited_access?
        return false if has_ci_access?
        @internal.dig(:copilot_settings, :o3_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o_ff_enabled?
        return false if !has_premium_access?
        @internal.dig(:copilot_settings, :o_ff_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o_ff_disabled?
        return true if !has_premium_access?
        @internal.dig(:copilot_settings, :o_ff_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def ofct_enabled?
        return false if has_limited_access?

        @internal.dig(:copilot_settings, :ofct_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def ofct_disabled?
        return true if has_limited_access?

        @internal.dig(:copilot_settings, :ofct_disabled) || false
      end

      # Note: has_pro_plus_access may need to be moved out this in the future when we add more features for max.
      sig { returns(T::Boolean) }
      memoize def has_premium_access?
        has_pro_plus_access? || has_ce_access? || has_max_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_required_sku_for_copilot_coding_agent?
        return false if has_limited_access?
        has_premium_access? || has_cb_access? || has_ci_access? || has_trial_access?
      end

      sig { returns(T::Boolean) }
      memoize def any_business_or_org_has_fsi_enabled?
        business_enabled = copilot_businesses.any? { |business| business.feature_flag_enabled_or_raise?(:copilot_api_force_legacy_base_chat_model) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return true if business_enabled
        org_enabled = copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_api_force_legacy_base_chat_model) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        org_enabled
      end

      sig { returns(T::Boolean) }
      memoize def obmb_enabled?
        return false if has_limited_access?
        @internal.dig(:copilot_settings, :obmb_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def obmb_disabled?
        return true if has_limited_access?
        @internal.dig(:copilot_settings, :obmb_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def obmw_enabled?
        @internal.dig(:copilot_settings, :obmw_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def obmw_disabled?
        @internal.dig(:copilot_settings, :obmw_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def ofo_enabled?
        return true unless any_business_or_org_has_fsi_enabled?

        return true if has_limited_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return true if has_ci_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        @internal.dig(:copilot_settings, :ofo_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def ofo_disabled?
        return false unless any_business_or_org_has_fsi_enabled?
        return true if has_limited_access?

        return false if has_limited_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if has_ci_access? && user_object.feature_flag_enabled_or_raise?(:copilot_ofo_cfi_on) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        @internal.dig(:copilot_settings, :ofo_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def grok_code_enabled?
        return false if has_limited_access?
        @internal.dig(:copilot_settings, :grok_code_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def grok_code_disabled?
        return true if has_limited_access?
        @internal.dig(:copilot_settings, :grok_code_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def m_ironman_enabled?
        # This is just a template for a free model. DOUBLE CHECK THIS BEFORE USING IT
        return false if !user_object.feature_flag_enabled?(:copilot_m_ironman, default: false)
        @internal.dig(:copilot_settings, :m_ironman_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def m_ironman_disabled?
        # This is just a template for a free model. DOUBLE CHECK THIS BEFORE USING IT
        return true if !user_object.feature_flag_enabled?(:copilot_m_ironman, default: false)
        @internal.dig(:copilot_settings, :m_ironman_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def m_spiderman_enabled?
        # This is just a template for a pro model. DOUBLE CHECK THIS BEFORE USING IT
        return false if has_limited_access?
        @internal.dig(:copilot_settings, :m_spiderman_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def m_spiderman_disabled?
        # This is just a template for a pro model. DOUBLE CHECK THIS BEFORE USING IT
        return true if has_limited_access?
        @internal.dig(:copilot_settings, :m_spiderman_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def m_thor_enabled?
        # This is just a template for a pro plus model. DOUBLE CHECK THIS BEFORE USING IT
        return false if has_limited_access?
        @internal.dig(:copilot_settings, :m_thor_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def m_thor_disabled?
        # This is just a template for a pro plus model. DOUBLE CHECK THIS BEFORE USING IT
        return true if has_limited_access?
        @internal.dig(:copilot_settings, :m_thor_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def cli_enabled?
        @internal.dig(:copilot_settings, :cli_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def desktop_enabled?
        @internal.dig(:copilot_settings, :desktop_enabled) || false
      end

      sig { returns(T::Boolean) }
      def has_copilot_enterprise_access?
        organization_ids.any? && dotcom_chat_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def custom_models_enabled?
        @internal.dig(:copilot_settings, :custom_models_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def dotcom_chat_enabled?
        # if they have CI then dotcom chat is always enabled
        # otherwise we fall through to their cached settings
        return true if has_ci_access?

        @internal.dig(:copilot_settings, :dotcom_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def mobile_chat_enabled?
        @internal.dig(:copilot_settings, :mobile_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def pr_summarizations_enabled?
        return false if has_limited_access?
        # if they have CI then dotcom chat is always enabled
        # otherwise we fall through to their cached settings
        return true if has_ci_access?

        @internal.dig(:copilot_settings, :pr_summarizations_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def copilot_for_dotcom_enabled?
        pr_summarizations_enabled? && dotcom_chat_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def private_docs_enabled?
        @internal.dig(:copilot_settings, :private_docs_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def extensions_enabled?
        @internal.dig(:copilot_settings, :extensions_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def user_feedback_opt_in_enabled?
        # if they have CI then dotcom chat is always enabled
        # otherwise we fall through to their cached settings
        return true if has_ci_access?

        @internal.dig(:copilot_settings, :user_feedback_opt_in_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def beta_features_github_chat_enabled?
        return false if has_limited_access?

        # if they have CI then dotcom chat is always enabled
        # otherwise we fall through to their cached settings
        return true if has_ci_access?

        @internal.dig(:copilot_settings, :beta_features_github_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def token_billing_enabled?
        user_object.feature_flag_enabled?(:copilot_token_based_billing, default: false)
      end

      sig { returns(T::Boolean) }
      memoize def overages_enabled?
        return false if has_limited_access?

        snapshots = quota_snapshots
        return false if snapshots.nil? || snapshots.empty?

        overage_permitted = snapshots.dig("premium_interactions", :overage_permitted)
        return false if overage_permitted.nil?

        overage_permitted
      end

      sig { returns(T::Boolean) }
      memoize def overages_disabled?
        return true if has_limited_access?

        snapshots = quota_snapshots
        return true if snapshots.nil? || snapshots.empty?

        overage_permitted = snapshots.dig("premium_interactions", :overage_permitted)
        return true if overage_permitted.nil?

        !overage_permitted
      end

      sig { returns(T::Boolean) }
      memoize def enterprise_seat_usage_blocked?
        return false unless has_cb_access? || has_ce_access?
        return false unless use_token_based_billing?

        customer_id = resolve_usage_blocked_customer_id
        return true unless customer_id

        budget_blocked = fetch_budget_blocked?(customer_id)
        return true if budget_blocked

        cpwu_response = ::Billing::Platform::CanProceedWithUsage.call(
          ::Billing::Platform::CanProceedWithUsage::RequestParams.new(
            customer_id: customer_id.to_s,
            product: "copilot",
            sku: ::Billing::OveragePolicyConfiguration::COPILOT_AI_UNIT,
            actor_id: user_id || 0,
          )
        )
        cpwu_response.error.is_a?(::Billing::Platform::Api::Error)
      end

      sig { returns(T::Boolean) }
      memoize def swe_agent_enabled?
        return false unless has_required_sku_for_copilot_coding_agent?
        @internal.dig(:copilot_settings, :swe_agent_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def swe_agent_disabled?
        return true unless has_required_sku_for_copilot_coding_agent?
        @internal.dig(:copilot_settings, :swe_agent_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def mcp_enabled?
        return true if has_ci_access?
        return false if !has_required_sku_for_copilot_coding_agent?
        @internal.dig(:copilot_settings, :mcp_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def mcp_disabled?
        return false if has_ci_access?
        return true if !has_required_sku_for_copilot_coding_agent?
        @internal.dig(:copilot_settings, :mcp_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def spark_enabled?
        @internal.dig(:copilot_settings, :spark_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def spark_disabled?
        @internal.dig(:copilot_settings, :spark_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def code_review_enabled?
        return true if has_code_review_individual_access?
        @internal.dig(:copilot_settings, :code_review_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_code_review_individual_access?
        has_free_pro_access? || has_pro_plus_access? || has_pro_access? || has_trial_access? || has_max_access?
      end

      sig { returns(T::Boolean) }
      memoize def code_review_disabled?
        return false if has_code_review_individual_access?
        @internal.dig(:copilot_settings, :code_review_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def code_review_beta_features_enabled?
        return true if has_code_review_individual_access?
        @internal.dig(:copilot_settings, :code_review_beta_features_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def code_review_beta_features_disabled?
        return false if has_code_review_individual_access?
        @internal.dig(:copilot_settings, :code_review_beta_features_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def generated_commit_message_enabled?
        return false unless has_copilot_access?
        @internal.dig(:copilot_settings, :generated_commit_message_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def generated_commit_message_disabled?
        return false if !has_copilot_access?
        @internal.dig(:copilot_settings, :generated_commit_message_disabled) || false
      end

      sig { returns(::User) }
      def user_object
        user
      end

      sig { returns(T::Boolean) }
      memoize def eligible_for_trial?
        @internal.dig(:plan_details, :eligible_for_trial) || false
      end

      sig { returns(Integer) }
      memoize def days_left_on_trial
        @internal.dig(:plan_details, :days_left_on_trial) || -1
      end

      sig { returns(T::Boolean) }
      memoize def has_signed_up?
        has_copilot_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_subscription_ended?
        @internal.dig(:plan_details, :has_subscription_ended) || false
      end

      sig { returns(T::Boolean) }
      memoize def is_technical_preview_user?
        @internal.dig(:plan_details, :is_technical_preview_user) || false
      end

      sig { returns(T::Boolean) }
      memoize def technical_preview_user_lost_access?
        @internal.dig(:plan_details, :technical_preview_user_lost_access) || false
      end

      sig { returns(T::Boolean) }
      memoize def dashboard_entry_point_enabled?
        if @copilot_user.feature_flag_enabled?(:copilot_dashboard_entry_point_refactor, default: false)
          Copilot::Policies::DashboardEntryPoint.enabled?(@copilot_user)
        else
          user_object.settings.get(:copilot_dashboard_entry_point_enabled)
        end
      end

      sig { returns(T::Boolean) }
      memoize def show_copilot_functionality?
        return true if is_enterprise_managed?
        return true if has_cb_access? || has_ce_access?
        return true if has_copilot_individual_pro_access?
        return true if has_copilot_individual_max_access?

        user_object.settings.get(:copilot_show_functionality)
      end

      delegate :quota_reset_date, :quota_reset_date_utc, :quota_percentage_remaining,
        :quota_feature_entitlement, :quota_feature_overage_count,
        :quota_snapshots, :billable_customer_id, :copilot_plan,
        :copilot_provider, :use_token_based_billing?,
        :can_upgrade_plan?, to: :@copilot_user

      delegate :feature_flag_enabled?, to: :@user

      sig { params(feature: String).returns(String) }
      def quota_id(feature:)
        case feature
        when "chat"
          has_limited_access? ? "free_chat" : "premium_chat"
        when "completions"
          "free_completions"
        when "premium_interactions"
          "premium_interactions"
        when "immediate_usage_interval"
          "immediate_usage_interval"
        when "extended_usage_interval"
          "extended_usage_interval"
        else
          "invalid_feature"
        end
      end

      sig { returns(T::Array[Integer]) }
      memoize def copilot_customer_ids
        return [@user.customer&.id] if has_copilot_individual_pro_access?
        return [@user.customer&.id] if has_copilot_individual_max_access?

        seats = copilot_seats.to_a
        if @user.feature_flag_enabled?(:copilot_prefill_public_user_associations, default: false)
          prefill_seat_owners(seats)
        end
        customer_ids_from_seats(seats)
      end

      sig { returns(T::Array[Integer]) }
      memoize def billable_customer_ids
        return copilot_customer_ids unless copilot_customer_ids.size > 1

        [billable_customer_id].compact
      end

      sig { returns(T.nilable(Integer)) }
      def provider_customer_id
        billable_customer_ids.first
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def copilot_seats
        Copilot::Seat.without_access_revoked_for_user(@copilot_user.id)
      end

      sig { returns(T::Hash[Symbol, String]) }
      memoize def policy_values
        @internal.dig(:copilot_policies) || {}
      end

      sig { returns(T::Boolean) }
      def cli_remote_control_enabled?
        policy_values[:cli_remote_control] == "enabled"
      end

      sig { returns(T::Boolean) }
      def cli_cloud_session_storage_enabled?
        policy_values[:cli_cloud_session_storage] == "enabled"
      end

      # Whether the user can view remote sessions on dotcom.
      sig { returns(T::Boolean) }
      def cloud_agent_sessions_visible?
        return false unless has_copilot_access?
        return false unless show_copilot_functionality?

        if has_ci_access? || has_limited_access?
          policy_values[:cli] == "enabled"
        else
          return true if cli_remote_control_enabled?
          return false unless feature_flag_enabled?(:copilot_mission_control_cloud_session_tab, default: false)
          cli_cloud_session_storage_enabled?
        end
      end

      # Model Registry Models
      sig { returns(T::Hash[String, String]) }
      memoize def model_policies
        @internal.dig(:model_registry, :model_policies) || {}
      end

      sig { params(model_key: String).returns(T::Boolean) }
      def model_enabled?(model_key)
        model_policies[model_key] == "enabled"
      end

      sig { params(model_key: String).returns(T::Boolean) }
      def model_disabled?(model_key)
        model_policies[model_key] == "disabled"
      end

      sig { params(model_key: String).returns(T::Boolean) }
      def model_unconfigured?(model_key)
        model_policies[model_key] == "unconfigured"
      end

      sig { params(model_key: String).returns(String) }
      def model_policy(model_key)
        model_policies[model_key] || "unconfigured"
      end

      private

      sig { params(user: ::User, check_models_staleness: T::Boolean).void }
      def initialize(user, check_models_staleness: false)
        @user                     = user
        @user_id                  = T.let(nil, T.nilable(Integer))
        @analytics_tracking_id    = T.let(nil, T.nilable(String))
        # Mirror the rescue in `request_cache_key`; fall back to nil ids (downstream readers
        # already handle nilable ids).
        user_lookup_failed = T.let(false, T::Boolean)
        begin
          @user_id = user.id
          @analytics_tracking_id = user.analytics_tracking_id
        rescue NoMethodError => e
          user_lookup_failed = true
          Failbot.report(e,
            "code.namespace": "Copilot::Public::User",
            "code.function": "initialize",
            "user.class": user.class.name,
          )
        end
        @copilot_user             = T.let(Copilot::User.new(@user), Copilot::User)
        @internal                 = T.let(Hash.new, T::Hash[Symbol, T.untyped])  # rubocop:disable Sorbet/ForbidTUntyped
        @check_models_staleness   = T.let(check_models_staleness, T::Boolean)

        # Skip cache load when `user.id` raised; `load_from_cache` would re-raise.
        with_database_error_fallback { load_from_cache } unless user_lookup_failed
      end

      sig { void }
      def load_from_cache
        return unless build_cache_on_initialize

        # start time for datadog cache load metric
        start = GitHub::Dogstats.monotonic_time

        cached_user = {}
        begin
          cached_user = Copilot::UserCache.new(user: @user).read
        rescue JSON::ParserError => e
          # Handle corrupted cache gracefully - log and rebuild
          GitHub.logger.warn("Corrupted copilot cache data, rebuilding", {
            "code.namespace": "Copilot::Public::User",
            "code.function": "load_from_cache",
            "gh.user.id": @user.id,
            "error": e.message,
          })
          cached_user = {}
        end

        @internal = cached_user

        # if we are storing the cache in redis, the TTL is handled by remote cache
        cache_expired = cached_user.fetch(:timestamp, 0).to_i < cache_refresh_interval.ago.to_i && !cache_in_redis?

        models_changed = @check_models_staleness && !cached_user.empty? && models_cache_stale?

        if cached_user.empty? || cached_user.fetch(:version, 0) < Copilot::PolicyCacheVersion.minimum_version || cache_expired || models_changed
          GitHub.logger.info("Refreshing Copilot cache for user", {
            "code.namespace": "Copilot::Public::User",
            "code.function": "load_from_cache",
            "gh.user.id": @user.id,
            "gh.copilot.cache.expired": cache_expired,
            "gh.copilot.cache.models_changed": models_changed,
          })
          reload_user_settings
          if @internal.empty?
            GitHub.logger.warn("Copilot settings cache still empty after correction attempt", {
              "code.namespace": "Copilot::Public::User",
              "code.function": "load_from_cache",
              "gh.user.id": @user.id,
              # Tracks whether the cache was already empty on the initial read, before reload_user_settings ran.
              # When true, the user's settings could never be computed at all; when false, the cache had data but the
              # reload cleared it.
              "gh.copilot.cache.initial_empty": cached_user.empty?,
            })
          end
        # cache does not need refresh, send cache hit metric to datadog
        else
          dd_license_type = if has_ci_access?
            "cfi"
          elsif has_cb_access? || has_ce_access?
            "cfb"
          else
            "no access"
          end
          now = GitHub::Dogstats.monotonic_time
          GitHub.dogstats.distribution("copilot.settings_cache.load_time", GitHub::Dogstats.duration(start, now), tags: ["copilot_license:#{dd_license_type}"])
        end
      end

      sig { returns(T::Boolean) }
      def models_cache_stale?
        # If no model registry data in cache, not stale (nothing to compare)
        model_registry = @internal.dig(:model_registry)
        return false if model_registry.nil?

        model_policies = model_registry[:model_policies]
        return false unless model_policies # nil check

        # Get feature flag snapshot from cache (added for efficient staleness detection)
        ff_snapshot = model_registry[:ff_snapshot]

        # If empty AND last checked recently, don't re-check
        # This prevents hammering for_user on every request for users with no models
        # while still eventually detecting when models become available (e.g., via FF changes)
        if model_policies.empty?
          last_checked = model_registry[:models_last_checked_at]
          if last_checked && Time.parse(last_checked) > 5.minutes.ago
            return false # Not stale, checked recently
          end
          # Fall through to check if it's been a while or never checked
        end

        # Fast check: Compare current feature flag states and registry state with cached snapshot
        # This avoids expensive for_user call with organization loading
        if ff_snapshot
          # Completely disable staleness detection — useful during large rollouts to
          # prevent any user-driven cache rebuilds while admin propagation catches up.
          return false if @user.feature_flag_enabled?(:copilot_disable_staleness_check, default: false)

          # Rate-limit staleness-triggered rebuilds to avoid thundering herd when
          # models or feature flags change — all users would detect staleness simultaneously.
          # Admin-driven propagation (via background jobs) bypasses this check entirely.
          # Deterministic per-user jitter (0 to staleness_jitter_range) spreads checks across users.
          if @user.feature_flag_enabled?(:copilot_staleness_rate_limit, default: false)
            last_checked = model_registry[:models_last_checked_at]
            rate_limit = self.class.staleness_rate_limit(@user)
            jitter_range = self.class.staleness_jitter_range(@user)
            jitter = (Digest::SHA256.hexdigest(@user.id.to_s).first(8).to_i(16) % jitter_range.to_i).seconds
            if last_checked && Time.parse(last_checked) > (rate_limit + jitter).ago
              return false
            end
          end

          # Check if models were added/removed from the registry.
          # When copilot_skip_rebuild_for_inaccessible_models is enabled, we track the change
          # and fall through to the user_models_hash check below instead of
          # immediately returning true. This avoids a mass cache rebuild (write
          # to users table) for ALL users whenever a new model is added — even
          # if it's behind a feature flag that nobody has access to yet.
          all_models = Copilot::ModelsRegistryCache.all_cached
          current_registry_hash = Digest::SHA256.hexdigest(all_models.map(&:model_key).sort.join(","))
          cached_registry_hash = ff_snapshot[:registry_hash]

          if cached_registry_hash && current_registry_hash != cached_registry_hash
            if @user.feature_flag_enabled?(:copilot_skip_rebuild_for_inaccessible_models, default: false)
              registry_changed = true
            else
              return true
            end
          else
            registry_changed = false
          end

          current_internal_ff = @copilot_user.feature_flag_enabled?(:copilot_registry_internal_models_testing, default: false)

          # Check if internal models FF changed
          return true if ff_snapshot[:internal_models] != current_internal_ff

          # Check if any model-specific FF changed
          cached_model_flags = ff_snapshot[:model_flags] || {}
          cached_model_flags.each do |flag_name, cached_state|
            current_state = @copilot_user.feature_flag_enabled?(flag_name.to_sym, default: false)
            return true if cached_state != current_state
          end

          # Comprehensive check: Compare user's actual available models.
          # This catches plan changes and registry changes (new model added/removed)
          # but calls for_user, which loads orgs/businesses from the DB and checks
          # feature flags for every model in the registry.
          # The rate limit above reduces how often we reach this point (30-60 min
          # jitter window), and CI users skip models_cache_stale? entirely.
          # Normally only run if cache is old enough (5+ minutes) to amortize cost,
          # but when the registry changed we bypass the age gate so we can determine
          # whether the user's actual models differ — without that, we'd either
          # trigger a needless rebuild or miss a real change.
          cached_user_models_hash = ff_snapshot[:user_models_hash]
          if cached_user_models_hash
            last_checked = model_registry[:models_last_checked_at]
            cache_is_old = !last_checked || Time.parse(last_checked) <= 5.minutes.ago

            if cache_is_old || registry_changed
              # When the registry changed but the user's models didn't, the cached
              # registry_hash stays outdated (no rebuild occurred). Without this
              # guard the expensive for_user call would repeat on every subsequent
              # request. A short-lived memcached key, keyed on [user_id,
              # current_registry_hash], remembers that we already verified this
              # registry version for this user. The key auto-expires so we
              # periodically re-verify, and it naturally invalidates when the
              # registry changes again (new hash).
              if registry_changed
                registry_check_cache_key = "copilot:registry_check:#{@user.id}:#{current_registry_hash}"
                return false if GitHub.cache.exist?(registry_check_cache_key)
              end

              expected_models = @copilot_user.registry_models
              current_user_models_hash = Digest::SHA256.hexdigest(expected_models.map(&:model_key).sort.join(","))

              if current_user_models_hash != cached_user_models_hash
                return true
              elsif registry_changed
                # User's models didn't change despite registry mismatch — remember
                # this result to avoid repeating the expensive check.
                GitHub.cache.write(registry_check_cache_key, true, expires_in: 10.minutes)
              end
            end
          end

          # Nothing changed - not stale
          return false
        end

        # Fallback: No ff_snapshot, do expensive check (old cache format or error)
        expected_models = @copilot_user.registry_models
        expected_keys = expected_models.map(&:model_key).sort
        cached_keys = model_policies.keys.map(&:to_s).sort

        expected_keys != cached_keys
      rescue => e
        # If there's any error checking staleness (e.g., database unavailable),
        # assume NOT stale to prevent cache regeneration that could wipe out existing models.
        # This preserves user's existing model access during database outages.
        GitHub.logger.warn("Error checking models cache staleness, preserving existing cache", {
          "code.namespace": "Copilot::Public::User",
          "code.function": "models_cache_stale?",
          "gh.user.id": @user.id,
          "error": e.message,
          "error.class": e.class.name,
        })
        false
      end

      sig { void }
      def reload_user_settings
        @copilot_user.create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "cache_stale_or_missing")
        @internal = Copilot::UserCache.new(user: @user).read
      end

      sig { returns(T::Array[Copilot::Organization]) }
      memoize def live_copilot_organizations
        seats = copilot_seats.to_a
        if @user.feature_flag_enabled?(:copilot_prefill_public_user_associations, default: false)
          prefill_seat_owners(seats)
        end
        live_orgs_from_seats(seats)
      end

      # Helper methods for Scientist experiments: prefill vs no-prefill paths

      # Eagerly load the polymorphic owner → business → customer chain.
      # Must be done after seats are materialized because owner is polymorphic:
      # Organizations have :business (→ :customer), Businesses have :customer directly.
      sig { params(seats: T::Array[Copilot::Seat]).void }
      def prefill_seat_owners(seats)
        return if seats.empty?

        GitHub::PrefillAssociations.prefill_associations(seats, :seat_assignment)

        assignments = seats.filter_map(&:seat_assignment)
        return if assignments.empty?

        GitHub::PrefillAssociations.prefill_associations(assignments, :owner)

        owners = assignments.filter_map(&:owner)

        businesses = owners.select { |o| o.is_a?(::Business) }
        GitHub::PrefillAssociations.prefill_associations(businesses, :customer) unless businesses.empty?

        orgs = owners.select { |o| o.is_a?(::Organization) }
        unless orgs.empty?
          GitHub::PrefillAssociations.prefill_associations(orgs, :business)
          org_businesses = orgs.filter_map(&:business)
          GitHub::PrefillAssociations.prefill_associations(org_businesses, :customer) unless org_businesses.empty?
        end
      end

      sig { params(seats: T::Array[Copilot::Seat]).returns(T::Array[Integer]) }
      def customer_ids_from_seats(seats)
        seats.filter_map do |seat|
          assignment = seat.seat_assignment
          next unless assignment

          owner = assignment.owner

          if owner.is_a?(::Business)
            owner.customer&.id
          elsif owner.is_a?(::Organization)
            ob = owner.business
            if ob
              ob.customer&.id
            else
              owner.customer&.id
            end
          end
        end.uniq
      end

      sig { params(seats: T::Array[Copilot::Seat]).returns(T::Array[Copilot::Organization]) }
      def live_orgs_from_seats(seats)
        seats.filter_map do |seat|
          assignment = seat.seat_assignment
          next unless assignment
          next unless assignment.owner_type == "Organization"

          Copilot::Organization.new(assignment.owner)
        end
      end

      sig { returns(T::Boolean) }
      def cache_in_redis?
        @internal.dig(:source) == "redis"
      end

      sig { returns(T.nilable(Integer)) }
      def resolve_usage_blocked_customer_id
        explicit_id = billable_customer_id
        return explicit_id if explicit_id.present?

        ids = copilot_customer_ids
        return nil if ids.size != 1

        ids.first
      end

      sig { params(customer_id: Integer).returns(T::Boolean) }
      def fetch_budget_blocked?(customer_id)
        response = ::Billing::Platform::Api::Client.new.get_all_budgets(
          customer_id: customer_id,
          user_id: (user_id || 0).to_s,
          budget_target: "premium_requests",
          scope: "multi_user_customer",
        )

        response.is_a?(::Billing::Platform::Api::Error)
      end
    end
  end
end
