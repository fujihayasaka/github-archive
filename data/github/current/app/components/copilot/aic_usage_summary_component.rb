# typed: strict
# frozen_string_literal: true

module Copilot
  class AicUsageSummaryComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    # This component renders synchronously during the page request, so bound the
    # billing-platform calls with an explicit timeout. Without one, a slow
    # response can consume the entire request budget and time out the page. On
    # timeout the client returns Billing::Platform::Api::Error, which the budget
    # and spending-info helpers already handle by failing closed.
    BILLING_PLATFORM_TIMEOUT_SECONDS = T.let(1.0, Float)

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = copilot_user

      @entitlement = T.let(0, Integer)
      @entitlement_used = T.let(0, Integer)
      @entitlement_percent_used = T.let(0.0, Float)
      @entitlement_reset_label = T.let("", String)

      # Overage spend (premium_interactions quota)
      @overage_spent = T.let("$0.00", String)
      @overage_budget = T.let("$0", String)
      @overage_percent_used = T.let(0.0, Float)
      @budget_overage_status_label = T.let("Not enabled", String)
      @overage_permitted = T.let(false, T::Boolean)

      # Budget data for edit dialog
      @budget_uuid = T.let(nil, T.nilable(String))
      @budget_amount = T.let(0, Integer)
      @customer_id = T.let(nil, T.nilable(String))
      @has_budget = T.let(false, T::Boolean)

      # Usage banner state
      @usage_banner_scheme = T.let(nil, T.nilable(Symbol))
      @usage_banner_message = T.let(nil, T.nilable(String))

      # Upgrade CTA state
      @show_upgrade_cta = T.let(false, T::Boolean)
      @show_persistent_upgrade_cta = T.let(false, T::Boolean)
      @is_free_user = T.let(@copilot_user.has_limited_access?, T::Boolean)

      return unless @copilot_user.has_cfi_access?

      if @copilot_user.consumptive_user?
        load_overage_quota
        load_budget_data
        compute_credit_quota
        compute_usage_banner
      end

      @entitlement_reset_label = Copilot::QuotaDataHelper.format_reset_label(@copilot_user.quota_reset_date, time_zone: user_time_zone)
    end

    sig { returns(T::Boolean) }
    def render?
      @copilot_user.has_cfi_access? && (@copilot_user.consumptive_user?)
    end

    sig { returns(T.nilable(Copilot::TrustTierLimitHitBannerPayload::Payload)) }
    memoize def trust_limit_banner_payload
      Copilot::TrustTierLimitHitBannerPayload.build(
        copilot_user: @copilot_user,
        billing_platform_client: billing_platform_client,
        time_zone: user_time_zone,
        class_name: "rounded-top-0",
      )
    end

    sig { returns(T::Boolean) }
    def merge_with_banner_below?
      trust_limit_banner_payload.present? || @usage_banner_message.present?
    end

    private

    sig { void }
    def load_overage_quota
      snapshot = @copilot_user.quota_snapshots["premium_interactions"]
      return unless snapshot

      @overage_permitted = snapshot[:overage_permitted] || false
    end

    sig { void }
    def load_budget_data
      customer = @copilot_user.user_object.customer
      return unless customer

      @customer_id = customer.id.to_s

      result = Copilot::QuotaDataHelper.fetch_budget_spend(client: billing_platform_client, customer_id: @customer_id)
      return unless result

      if result[:target_amount].to_i > 0
        @budget_overage_status_label = "Enabled"
        @has_budget = true
      end

      @budget_uuid = result[:uuid]
      @budget_amount = result[:target_amount]
      @overage_budget = number_to_currency(@budget_amount, precision: 0)

      current_spend = result[:current_spend]
      @overage_spent = number_to_currency(current_spend)
      @overage_percent_used = Copilot::QuotaDataHelper.real_budget_percent_used(current_spend, @budget_amount)
    rescue StandardError => e
      Failbot.report(e,
        "code.namespace" => "Copilot::AicUsageSummaryComponent",
        "code.function" => "load_budget_data",
      )
    end

    sig { returns(::Billing::Platform::Api::Client) }
    def billing_platform_client
      if @copilot_user.feature_flag_enabled?(:copilot_settings_billing_timeout, default: false)
        ::Billing::Platform::Api::Client.new(timeout: BILLING_PLATFORM_TIMEOUT_SECONDS)
      else
        ::Billing::Platform::Api::Client.new
      end
    end

    sig { params(percent_used: Float, reset_label: String).returns(String) }
    def reset_label_for(percent_used, reset_label)
      return "No usage yet" if percent_used == 0.0

      reset_label
    end

    sig { returns(ActiveSupport::TimeZone) }
    def user_time_zone
      @copilot_user.user_object.time_zone
    end

    sig { returns(T::Boolean) }
    def paid_usage_exhausted?
      @copilot_user.consumptive_user? && @entitlement_percent_used >= 100.0
    end

    sig { returns(T::Boolean) }
    def overage_has_headroom?
      @overage_permitted && @overage_percent_used < 100.0
    end

    sig { returns(T::Boolean) }
    def overage_budget_hit?
      @overage_permitted && @overage_percent_used >= 100.0
    end

    sig { returns(T::Boolean) }
    def system_limit_hit?
      !@overage_permitted && @has_budget
    end

    sig { returns(T::Boolean) }
    def show_banner_actions?
      return true if @show_upgrade_cta
      return true if show_budget_cta?

      false
    end

    sig { returns(T::Boolean) }
    def show_budget_cta?
      return false unless @customer_id.present?
      return false if overage_has_headroom?
      return false if system_limit_hit?

      true
    end

    sig { returns(T::Boolean) }
    def free_user?
      @is_free_user
    end

    sig { returns(T::Boolean) }
    def upgrade_eligible?
      free_user? || @copilot_user.has_pro_subscription? || @copilot_user.has_pro_plus_subscription?
    end

    sig { void }
    def set_upgrade_cta
      return unless upgrade_eligible?

      @show_upgrade_cta = true
    end

    sig { returns(String) }
    memoize def upgrade_url
      if @copilot_user.has_pro_subscription?
        copilot_pro_plus_signup_path
      else
        copilot_max_signup_path
      end
    end

    sig { void }
    def compute_usage_banner
      if paid_usage_exhausted?
        if overage_has_headroom?
          @usage_banner_scheme = :default
          @usage_banner_message = "You're now using additional usage until your included credits reset on #{Copilot::QuotaDataHelper.short_usage_reset_date(@copilot_user, time_zone: user_time_zone)}."
        elsif overage_budget_hit?
          @usage_banner_scheme = :danger
          @usage_banner_message = "You've reached your additional usage budget of AI credits. Increase your budget to continue usage, or wait until your credits reset on #{Copilot::QuotaDataHelper.short_usage_reset_date(@copilot_user, time_zone: user_time_zone)}."
          set_upgrade_cta
        elsif system_limit_hit?
          @usage_banner_scheme = :danger
          @usage_banner_message = "You've reached your additional usage limit for your plan. Upgrade your plan to continue or wait until your credits reset on #{Copilot::QuotaDataHelper.short_usage_reset_date(@copilot_user, time_zone: user_time_zone)}."
          set_upgrade_cta
        else
          @usage_banner_scheme = :danger
          @usage_banner_message = "You've run out of your included AI credits for the month. Limit resets on #{Copilot::QuotaDataHelper.short_usage_reset_date(@copilot_user, time_zone: user_time_zone)}."
          set_upgrade_cta
        end
      end
    end

    sig { void }
    def compute_credit_quota
      snapshot = @copilot_user.quota_snapshots["premium_interactions"] || {}

      @entitlement = snapshot.fetch(:entitlement, 0) || 0
      quota_remaining = (snapshot[:quota_remaining] || snapshot[:remaining] || 0).clamp(0, @entitlement)
      @entitlement_used = (@entitlement.to_d - quota_remaining.to_d).to_f.round
      @entitlement_percent_used = if @entitlement <= 0
        0.0
      else
        Copilot::QuotaDataHelper.format_percentage_used(@entitlement_used / @entitlement.to_f * 100)
      end
    end
  end
end
