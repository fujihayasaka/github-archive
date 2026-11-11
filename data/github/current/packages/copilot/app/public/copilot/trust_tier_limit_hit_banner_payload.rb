# typed: strict
# frozen_string_literal: true

module Copilot
  class TrustTierLimitHitBannerPayload
    include GitHub::Memoizer

    NotEligiblePayload = T.type_alias do
      {
        variant: String,
        resetDate: String,
        className: T.nilable(String),
      }
    end

    WithHeadroomPayload = T.type_alias do
      {
        variant: String,
        currentPlanName: String,
        upgradeTargetName: String,
        upgradePriceUsd: Numeric,
        creditOffsetUsd: Numeric,
        payAmountUsd: Numeric,
        resetDate: String,
        upgradeUrl: String,
        className: T.nilable(String),
      }
    end

    CutUsagePayload = T.type_alias do
      {
        variant: String,
        currentPlanName: String,
        upgradeTargetName: String,
        upgradePriceUsd: Numeric,
        payAmountUsd: Numeric,
        remainingOverageAfterUpgradeUsd: Numeric,
        resetDate: String,
        upgradeUrl: String,
        className: T.nilable(String),
      }
    end

    Payload = T.type_alias { T.any(NotEligiblePayload, WithHeadroomPayload, CutUsagePayload) }

    UpgradeTarget = T.type_alias do
      {
        name: String,
        entitlement: Integer,
        price_usd: Integer,
      }
    end

    sig do
      params(
        copilot_user: Copilot::User,
        billing_platform_client: ::Billing::Platform::Api::Client,
        time_zone: ActiveSupport::TimeZone,
        class_name: T.nilable(String),
      ).returns(T.nilable(Payload))
    end
    def self.build(copilot_user:, billing_platform_client:, time_zone:, class_name: nil)
      new(
        copilot_user: copilot_user,
        billing_platform_client: billing_platform_client,
        time_zone: time_zone,
        class_name: class_name,
      ).build
    end

    sig do
      params(
        copilot_user: Copilot::User,
        billing_platform_client: ::Billing::Platform::Api::Client,
        time_zone: ActiveSupport::TimeZone,
        class_name: T.nilable(String),
      ).void
    end
    def initialize(copilot_user:, billing_platform_client:, time_zone:, class_name: nil)
      @copilot_user = copilot_user
      @billing_platform_client = billing_platform_client
      @time_zone = time_zone
      @class_name = class_name
    end

    sig { returns(T.nilable(Payload)) }
    def build
      return nil if GitHub.enterprise?
      return nil unless feature_flag_enabled?
      return nil unless spending_info&.dig(:limit_reached)

      if !trust_limit_upgrade_eligible?
        not_eligible_payload
      elsif trust_limit_has_credit_headroom?
        with_headroom_payload
      else
        cut_usage_payload
      end
    end

    private

    sig { returns(NotEligiblePayload) }
    def not_eligible_payload
      {
        variant: "not_eligible",
        resetDate: reset_date,
        className: @class_name,
      }
    end

    sig { returns(WithHeadroomPayload) }
    def with_headroom_payload
      {
        variant: "with_headroom",
        currentPlanName: current_plan_name,
        upgradeTargetName: upgrade_target[:name],
        upgradePriceUsd: upgrade_price_usd,
        creditOffsetUsd: upgrade_credit_offset,
        payAmountUsd: spending_overage_amount,
        resetDate: reset_date,
        upgradeUrl: upgrade_url,
        className: @class_name,
      }
    end

    sig { returns(CutUsagePayload) }
    def cut_usage_payload
      {
        variant: "cut_usage",
        currentPlanName: current_plan_name,
        upgradeTargetName: upgrade_target[:name],
        upgradePriceUsd: upgrade_price_usd,
        payAmountUsd: spending_overage_amount,
        remainingOverageAfterUpgradeUsd: [spending_overage_amount - upgrade_credit_delta_dollars, 0.0].max,
        resetDate: reset_date,
        upgradeUrl: upgrade_url,
        className: @class_name,
      }
    end

    sig { returns(Numeric) }
    def upgrade_price_usd
      upgrade_target[:price_usd] - current_plan_price_usd
    end

    sig { returns(String) }
    def reset_date
      Copilot::QuotaDataHelper.iso_usage_reset_date(@copilot_user, time_zone: @time_zone)
    end

    sig { returns(T::Boolean) }
    def feature_flag_enabled?
      FeatureFlag.vexi.enabled?(:copilot_cfi_cap_hit_banner, @copilot_user.user_object, default: false)
    end

    sig { returns(T.nilable(Copilot::QuotaDataHelper::SpendingInfo)) }
    memoize def spending_info
      Copilot::QuotaDataHelper.fetch_copilot_spending_info(
        client: @billing_platform_client,
        copilot_user: @copilot_user,
      )
    end

    sig { returns(Float) }
    def spending_overage_amount
      spending_info&.dig(:overage_amount).to_f
    end

    sig { returns(T::Boolean) }
    def trust_limit_upgrade_eligible?
      return false unless @copilot_user.can_upgrade_plan?
      return false if upgrade_target[:price_usd] <= 0

      true
    end

    sig { returns(T::Boolean) }
    def trust_limit_has_credit_headroom?
      upgrade_credit_offset > 0
    end

    sig { returns(Float) }
    def upgrade_credit_offset
      [upgrade_credit_delta_dollars - spending_overage_amount, 0.0].max
    end

    # AI Credits: $0.01 per credit.
    sig { returns(Float) }
    def upgrade_credit_delta_dollars
      delta = upgrade_target[:entitlement] - current_entitlement
      return 0.0 if delta <= 0

      delta * 0.01
    end

    sig { returns(Integer) }
    def current_entitlement
      snapshot = @copilot_user.quota_snapshots["premium_interactions"] || {}
      snapshot.fetch(:entitlement, 0) || 0
    end

    sig { returns(UpgradeTarget) }
    memoize def upgrade_target
      if @copilot_user.has_educational_access?
        { name: Copilot::INDIVIDUAL_PRO_PRODUCT_NAME, entitlement: Copilot::Quotas::CFI_INCLUDED_AIC[:pro] || 0, price_usd: Copilot::COPILOT_PRO_MONTHLY_BASE_PRICE }
      elsif @copilot_user.has_pro_subscription?
        { name: Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_NAME, entitlement: Copilot::Quotas::CFI_INCLUDED_AIC[:pro_plus] || 0, price_usd: Copilot::COPILOT_PRO_PLUS_MONTHLY_BASE_PRICE }
      elsif @copilot_user.has_pro_plus_subscription?
        { name: Copilot::INDIVIDUAL_MAX_PRODUCT_NAME, entitlement: Copilot::Quotas::CFI_INCLUDED_AIC[:max] || 0, price_usd: Copilot::COPILOT_MAX_MONTHLY_BASE_PRICE }
      else
        { name: "", entitlement: 0, price_usd: 0 }
      end
    end

    sig { returns(String) }
    def current_plan_name
      # EDU users' managed_plan_product_name returns "Copilot Pro", so special-case
      # to surface "Copilot Student" in the banner.
      return Copilot::INDIVIDUAL_EDU_PRODUCT_NAME if @copilot_user.has_educational_access?

      @copilot_user.managed_plan_product_name
    end

    sig { returns(Integer) }
    def current_plan_price_usd
      if @copilot_user.has_educational_access?
        0
      elsif @copilot_user.has_pro_subscription?
        Copilot::COPILOT_PRO_MONTHLY_BASE_PRICE
      elsif @copilot_user.has_pro_plus_subscription?
        Copilot::COPILOT_PRO_PLUS_MONTHLY_BASE_PRICE
      elsif @copilot_user.has_max_subscription?
        Copilot::COPILOT_MAX_MONTHLY_BASE_PRICE
      else
        0
      end
    end

    sig { returns(String) }
    def upgrade_url
      if @copilot_user.has_educational_access?
        Rails.application.routes.url_helpers.copilot_pro_signup_path
      elsif @copilot_user.has_pro_subscription?
        Rails.application.routes.url_helpers.copilot_pro_plus_signup_path
      else
        Rails.application.routes.url_helpers.copilot_max_signup_path
      end
    end
  end
end
