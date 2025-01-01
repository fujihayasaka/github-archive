# typed: strict
# frozen_string_literal: true

module Copilot
  module Public
    class User
      include T::Helpers
      include GitHub::Memoizer
      include GitHub::ResilienceMixin

      cattr_accessor :build_cache_on_initialize, default: !GitHub::AppEnvironment.test?

      # About versioning:
      # CURRENT_VERSION is the version of the cache that is being written to User.settings.
      # MINIMUM_VERSION is the minimum version of the cache that is acceptable to use as valid
      # data. If the cache is older than the minimum version, it will be reloaded. We might not need
      # these to always be in sync as features are developed to reduce the amount of reloading of data
      # for all users.
      CURRENT_VERSION = 17
      MINIMUM_VERSION = 17

      # Duration after which the cached Copilot policy data is considered stale and needs refreshing.
      # Used by load_from_cache to determine if user settings should be reloaded from the source.
      CACHE_REFRESH_INTERVAL = T.let(12.hours, ActiveSupport::Duration)

      sig { params(user: ::User).void }
      def self.for(user)
        new(user)
      end

      sig { returns(::User) }
      attr_reader :user

      sig { returns(T.nilable(::String)) }
      memoize def analytics_tracking_id
        @analytics_tracking_id
      end

      sig { returns(T.nilable(Integer)) }
      memoize def user_id
        @user_id
      end

      sig { returns(T::Array[::Organization]) }
      memoize def organization_ids
        @internal.dig(:settings, :organization_ids) || []
      end

      sig { returns(T::Array[::Business]) }
      memoize def business_ids
        @internal.dig(:settings, :business_ids) || []
      end

      sig { returns(T::Array[::Copilot::Organization]) }
      memoize def copilot_organizations
        ::Organization.where(id: organization_ids).map do |organization|
          Copilot::Organization.new(organization)
        end
      end

      sig { returns(T::Array[Copilot::Business]) }
      memoize def copilot_businesses
        return [] if business_ids.empty?

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

      # Free access in the context is actually Copilot Pro free access
      # Ex: OSS, Education, etc. users have free access to Copilot Pro
      # This is different from the free access that is available to all users
      sig { returns(T::Boolean) }
      memoize def has_free_pro_access?
        @internal.dig(:plan_details, :has_free_pro_access) || false
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

      sig { returns(T::Boolean) }
      memoize def has_copilot_individual_free_access?
        has_limited_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_individual_pro_access?
        has_ci_access? && !has_limited_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_access?
        has_paid_access? || has_free_pro_access? || has_trial_access? || has_limited_access? || has_cb_access? || has_ce_access?
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
      memoize def automatic_code_review_enabled?
        @internal.dig(:copilot_settings, :automatic_code_review_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def automatic_code_review_disabled?
        @internal.dig(:copilot_settings, :automatic_code_review_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def a_chat_enabled?
        @internal.dig(:copilot_settings, :a_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def a_chat_disabled?
        @internal.dig(:copilot_settings, :a_chat_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def a_f_enabled?
        return false if has_limited_access? && !user_object.feature_enabled?(:copilot_free_a_f)
        return true if has_ci_access?
        @internal.dig(:copilot_settings, :a_f_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def a_f_disabled?
        return true if has_limited_access? && !user_object.feature_enabled?(:copilot_free_a_f)
        return false if has_ci_access?
        @internal.dig(:copilot_settings, :a_f_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def afos_enabled?
        return false if !user_object.feature_enabled?(:copilot_afos)
        return false if has_limited_access?
        @internal.dig(:copilot_settings, :afos_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def afos_disabled?
        return true if !user_object.feature_enabled?(:copilot_afos)
        return true if has_limited_access?
        @internal.dig(:copilot_settings, :afos_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def al_enabled?
        return false if !user_object.feature_enabled?(:copilot_al)
        return false if !has_premium_access?

        @internal.dig(:copilot_settings, :al_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def al_disabled?
        return true if !user_object.feature_enabled?(:copilot_al)
        return true if !has_premium_access?

        @internal.dig(:copilot_settings, :al_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def g_chat_enabled?
        @internal.dig(:copilot_settings, :g_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def g_chat_disabled?
        @internal.dig(:copilot_settings, :g_chat_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def g_tf_enabled?
        return false if !user_object.feature_enabled?(:copilot_g_tf)
        return false if has_limited_access?

        @internal.dig(:copilot_settings, :g_tf_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def g_tf_disabled?
        return true if !user_object.feature_enabled?(:copilot_g_tf)
        return true if has_limited_access?

        @internal.dig(:copilot_settings, :g_tf_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def gtff_enabled?
        return false if !user_object.feature_enabled?(:copilot_gtff)
        @internal.dig(:copilot_settings, :gtff_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def gtff_disabled?
        return true if !user_object.feature_enabled?(:copilot_gtff)
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
      memoize def o_fm_enabled?
        return false if !user_object.feature_enabled?(:copilot_o_fm)
        return false if has_limited_access?
        return true if has_ci_access? && user_object.feature_enabled?(:copilot_o_fm_cfi_on)

        @internal.dig(:copilot_settings, :o_fm_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o_fm_disabled?
        return true if !user_object.feature_enabled?(:copilot_o_fm)
        return true if has_limited_access?
        return false if has_ci_access? && user_object.feature_enabled?(:copilot_o_fm_cfi_on)

        @internal.dig(:copilot_settings, :o_fm_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o_f_enabled?
        return true if has_ci_access? && user_object.feature_enabled?(:copilot_o_f) && user_object.feature_enabled?(:copilot_free_o_f)
        return false if has_limited_access?
        return true if has_ci_access? && user_object.feature_enabled?(:copilot_o_f)
        return false if has_ci_access?
        @internal.dig(:copilot_settings, :o_f_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o_f_disabled?
        return false if has_ci_access? && user_object.feature_enabled?(:copilot_o_f) && user_object.feature_enabled?(:copilot_free_o_f)
        return true if has_limited_access?
        return false if has_ci_access? && user_object.feature_enabled?(:copilot_o_f)
        return true if has_ci_access?
        @internal.dig(:copilot_settings, :o_f_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o_t_enabled?
        return false if !has_premium_access?
        return true if has_pro_plus_access? && user_object.feature_enabled?(:copilot_o_t_cfi_on)

        @internal.dig(:copilot_settings, :o_t_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def o_t_disabled?
        return false if has_pro_plus_access? && user_object.feature_enabled?(:copilot_o_t_cfi_on)
        return true if !has_premium_access?

        @internal.dig(:copilot_settings, :o_t_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def has_premium_access?
        has_pro_plus_access? || has_ce_access?
      end

      sig { returns(T::Boolean) }
      memoize def any_business_or_org_has_fsi_enabled?
        business_enabled = copilot_businesses.any? { |business| business.feature_enabled?(:copilot_api_force_legacy_base_chat_model) }
        return true if business_enabled
        org_enabled = copilot_organizations.any? { |org| org.feature_enabled?(:copilot_api_force_legacy_base_chat_model) }
        org_enabled
      end

      sig { returns(T::Boolean) }
      memoize def ofo_enabled?
        return true unless any_business_or_org_has_fsi_enabled?

        return true if has_limited_access? && user_object.feature_enabled?(:copilot_ofo_cfi_on)
        return true if has_ci_access? && user_object.feature_enabled?(:copilot_ofo_cfi_on)

        @internal.dig(:copilot_settings, :ofo_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def ofo_disabled?
        return false unless any_business_or_org_has_fsi_enabled?
        return true if has_limited_access?

        return false if has_limited_access? && user_object.feature_enabled?(:copilot_ofo_cfi_on)
        return false if has_ci_access? && user_object.feature_enabled?(:copilot_ofo_cfi_on)

        @internal.dig(:copilot_settings, :ofo_disabled) || false
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
      memoize def overages_enabled?
        return false if has_limited_access?
        @internal.dig(:copilot_settings, :overages_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def overages_disabled?
        return true if has_limited_access?
        @internal.dig(:copilot_settings, :overages_disabled) || true
      end

      sig { returns(T::Boolean) }
      memoize def swe_agent_enabled?
        return false if !has_premium_access?
        @internal.dig(:copilot_settings, :swe_agent_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def swe_agent_disabled?
        return true if !has_premium_access?
        @internal.dig(:copilot_settings, :swe_agent_disabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def mcp_enabled?
        return false if !has_premium_access?
        @internal.dig(:copilot_settings, :mcp_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def mcp_disabled?
        return true if !has_premium_access?
        @internal.dig(:copilot_settings, :mcp_disabled) || false
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
        user_object.settings.get(:copilot_dashboard_entry_point_enabled)
      end

      sig { returns(T::Boolean) }
      memoize def show_copilot_functionality?
        return true if is_enterprise_managed?
        return true if has_cb_access? || has_ce_access?
        return true if has_copilot_individual_pro_access?

        user_object.settings.get(:copilot_show_functionality)
      end

      delegate :quota_reset_date, :quota_percentage_remaining,
        :quota_feature_entitlement, :quota_feature_overage_count,
        :quota_snapshots, :billable_customer_id, :copilot_plan, :copilot_provider, to: :@copilot_user

      sig { params(feature: String).returns(String) }
      def quota_id(feature:)
        case feature
        when "chat"
          has_limited_access? ? "free_chat" : "premium_chat"
        when "completions"
          "free_completions"
        when "premium_interactions"
          "premium_interactions"
        else
          "invalid_feature"
        end
      end

      sig { returns(T::Array[Integer]) }
      memoize def copilot_customer_ids
        return [@user.customer&.id] if has_copilot_individual_pro_access?

        copilot_seats.map do |seat|
          owner = seat.seat_assignment.owner

          if owner.is_a?(::Business)
            # since the owner is a business, we'll try to return the customer id
            owner.customer&.id
          elsif owner.is_a?(::Organization)
            # since the owner is an org, we need to see if it is business linked
            ob = owner.business
            if ob
              # if the org has a business, we'll try to return the customer id of the business
              ob.customer&.id
            else
              # if the org does not have a business, we'll try to return the customer id of the org
              owner.customer&.id
            end
          end
        end.compact
      end

      sig { returns(T::Array[Integer]) }
      memoize def billable_customer_ids
        return copilot_customer_ids unless copilot_customer_ids.size > 1

        [billable_customer_id].compact
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def copilot_seats
        Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: @user.id)
      end

      private

      sig { params(user: ::User).void }
      def initialize(user)
        @user                  = user
        @user_id               = T.let(user.id, T.nilable(Integer))
        @analytics_tracking_id = T.let(user.analytics_tracking_id, T.nilable(String))
        @copilot_user          = T.let(Copilot::User.new(@user), Copilot::User)
        @internal              = T.let(Hash.new, T::Hash[Symbol, T.untyped])  # rubocop:disable Sorbet/ForbidTUntyped

        with_database_error_fallback { load_from_cache }
      end

      sig { void }
      def load_from_cache
        return unless build_cache_on_initialize
        cached_user = JSON.parse(@user.settings.get(:copilot_policy_data)).deep_symbolize_keys
        @internal = cached_user
        cache_expired = cached_user.fetch(:timestamp, 0).to_i < CACHE_REFRESH_INTERVAL.ago.to_i

        if cached_user.empty? || cached_user.fetch(:version, 0) < MINIMUM_VERSION || cache_expired
          GitHub.logger.info("Refreshing Copilot cache for user", {
            "code.namespace": "Copilot::Public::User",
            "code.function": "load_from_cache",
            "gh.user.id": @user.id,
            "gh.copilot.cache.expired": cache_expired,
          })
          reload_user_settings
        end
      end

      sig { void }
      def reload_user_settings
        @copilot_user.create_copilot_settings_cache(CURRENT_VERSION)
        @internal = JSON.parse(@user.settings.get(:copilot_policy_data)).deep_symbolize_keys
      end

      sig { returns(T::Array[Copilot::Organization]) }
      memoize def live_copilot_organizations
        copilot_seats.map do |seat|
          next unless seat.seat_assignment.owner_type == "Organization"

          Copilot::Organization.new(seat.seat_assignment.owner)
        end.compact
      end
    end
  end
end
