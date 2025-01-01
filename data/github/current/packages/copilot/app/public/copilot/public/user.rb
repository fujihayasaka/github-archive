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
      CURRENT_VERSION = 9
      MINIMUM_VERSION = 9

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
      memoize def public_code_suggestions_enabled?
        @internal.dig(:copilot_settings, :public_code_suggestions_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def ide_chat_enabled?
        @internal.dig(:copilot_settings, :chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def bing_github_chat_enabled?
        if user_object.feature_enabled?(:copilot_dotcom_chat_ci_and_cb)
          if has_ci_access?
            return @internal.dig(:copilot_settings, :bing_github_chat_enabled) if user_object.feature_enabled?(:copilot_dotcom_chat_bing_ci)
            return false
          end
          return false unless copilot_organizations.any?
          return copilot_organizations.all? do |org|
            org.bing_github_chat_enabled?
          end
        end
        @internal.dig(:copilot_settings, :bing_github_chat_enabled) || false
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
      memoize def g_chat_enabled?
        @internal.dig(:copilot_settings, :g_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def g_chat_disabled?
        @internal.dig(:copilot_settings, :g_chat_disabled) || false
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
      memoize def cli_enabled?
        @internal.dig(:copilot_settings, :cli_enabled) || false
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
        if user_object.feature_enabled?(:copilot_dotcom_chat_ci_and_cb)
          # if they have CI then dotcom chat is always enabled
          # otherwise we fall through to their cached settings
          return true if has_ci_access?
        end

        @internal.dig(:copilot_settings, :dotcom_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def mobile_chat_enabled?
        @internal.dig(:copilot_settings, :mobile_chat_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def pr_summarizations_enabled?
        if user_object.feature_enabled?(:copilot_dotcom_chat_ci_and_cb)
          # if they have CI then dotcom chat is always enabled
          # otherwise we fall through to their cached settings
          return true if has_ci_access?
        end

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
        if user_object.feature_enabled?(:copilot_dotcom_chat_ci_and_cb)
          return true if has_ci_access?

          return false unless copilot_organizations.any?
          return copilot_organizations.all? do |org|
            org.user_feedback_opt_in_enabled?
          end
        end
        @internal.dig(:copilot_settings, :user_feedback_opt_in_enabled) || false
      end

      sig { returns(T::Boolean) }
      memoize def beta_features_github_chat_enabled?
        # TODO: remove this live read once :copilot_dotcom_chat_ci_and_cb is deployed and version is bumped
        # https://github.slack.com/archives/C07J94L4VDH/p1726688290846289?thread_ts=1726679655.675549&cid=C07J94L4VDH
        if user_object.feature_enabled?(:copilot_dotcom_chat_ci_and_cb)
          return true if has_ci_access?
          return false unless copilot_organizations.any?
          return copilot_organizations.all? do |org|
            org.beta_features_github_chat_enabled?
          end
        end
        @internal.dig(:copilot_settings, :beta_features_github_chat_enabled) || false
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

      private

      sig { params(user: ::User).void }
      def initialize(user)
        @user                  = user
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

        if cached_user.empty? || cached_user.fetch(:version, 0) < MINIMUM_VERSION
          reload_user_settings
        end
      end

      sig { void }
      def reload_user_settings
        @copilot_user.create_copilot_settings_cache(CURRENT_VERSION)
        @internal = JSON.parse(@user.settings.get(:copilot_policy_data)).deep_symbolize_keys
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def copilot_seats
        Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: @user.id)
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
