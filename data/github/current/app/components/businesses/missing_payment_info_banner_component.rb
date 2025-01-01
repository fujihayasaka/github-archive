# typed: strict
# frozen_string_literal: true

class Businesses::MissingPaymentInfoBannerComponent < ApplicationComponent
  sig { params(business: T.nilable(Business), user: T.nilable(User)).void }
  def initialize(business:, user:)
    @business = business
    @user = user
  end

  sig { returns(T.nilable(Business)) }
  attr_reader :business

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?
    return false unless user.present?
    return false unless @business.present?
    # Only filter out disabled business if the ff is not set
    return false if @business.downgraded_to_free_plan? && !@business.feature_enabled?(:billing_cpwu_account_downgrade)
    # Trialed and did not convert (meaning they are still in trial or abandoned trial)
    return false if @business.trial? && !@business.trial_converted?
    return false unless customer = @business.customer
    return false unless customer.metered_ghe?
    return false unless customer.requires_azure_subscription?
    return false if customer.valid_metered_azure_payment_method?
    return false unless @business.feature_enabled?(:billing_cpwu_daily_customer_check_enabled)
    return false if @business.feature_enabled?(:billing_cpwu_daily_customer_check_exclusion_list)

    @business.owner?(user) || @business.billing_manager?(user)
  end

  private

  sig { void }
  def instrument
    analytics_label = {
      ref_business_id: business&.id,
      ref_billing_target: "azure",
      ref_days_since: business&.customer&.days_since_missing_payment_initial_notification
    }.compact.map { |k, v| "#{k}:#{v}" }.join(";")

    GlobalInstrumenter.instrument("analytics.event", {
      category: "missing_payment",
      action: "banner_displayed",
      label: analytics_label,
      actor: user,
    })
  end

  sig { returns(Date) }
  def disable_target_date
    initial_notification = business&.customer&.missing_payment_initial_notification || Date.today
    initial_notification.to_date + 30.days
  end

  sig { returns(T::Boolean) }
  def business_disabled?
    !!business&.disabled?
  end
end
