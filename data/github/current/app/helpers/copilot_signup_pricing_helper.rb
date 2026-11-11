# typed: strict
# frozen_string_literal: true

# Helper for calculating Copilot signup and upgrade pricing with coupon support.
# Uses Billing::Pricing for consistent discount calculations across all signup pages.
module CopilotSignupPricingHelper
  # Builds discount-aware pricing data for a Copilot product, applying any coupon the user holds.
  sig do
    params(
      product_key: String,
      user: User,
      billing_cycle: String
    ).returns(Billing::PricingDisplay::PricingData)
  end
  def copilot_signup_pricing(product_key:, user:, billing_cycle: "monthly")
    product_uuid = find_copilot_product_uuid(product_key, billing_cycle)
    coupon = user.coupon_for_product(Copilot::PRODUCT_TYPE, product_key)

    if coupon && product_uuid
      pricing = build_pricing_with_coupon(product_uuid, coupon)
      build_pricing_data_from_billing_pricing(pricing, coupon, billing_cycle)
    else
      build_pricing_data_without_coupon(product_uuid, billing_cycle)
    end
  end

  sig do
    params(
      product_key: String,
      user: User,
      copilot_user: Copilot::User
    ).returns(Copilot::CheckoutContext)
  end
  def copilot_checkout_context(product_key:, user:, copilot_user:)
    pricing_data = copilot_signup_pricing(product_key: product_key, user: user)
    new_entitlement = resolve_entitlement_for_product(product_key)

    spending_info = fetch_spending_info(copilot_user)
    current_overage = spending_info ? Billing::Money.new((spending_info[:overage_amount] * 100).round) : nil

    Copilot::CheckoutContext.build(
      pricing_data: pricing_data,
      upgrade_delta: compute_upgrade_price(copilot_user, product_key),
      eligible_for_trial: product_key == Copilot::INDIVIDUAL_PRO_PRODUCT_KEY && copilot_user.eligible_for_trial?,
      subscription_next_billing_date: copilot_user.copilot_active_subscription_item&.next_billing_date,
      coupon_redemption_expires_on: user.coupon_redemption&.expires_at&.to_date,
      new_entitlement: new_entitlement,
      current_overage: current_overage
    )
  end

  # Builds the included-credits clause appended to the billing summary sentence, e.g.:
  # ", which unlocks up to $70.00 in included credits"
  # ", which covers your additional usage and unlocks up to $70.00 in included credits"
  # Returns an empty string when the target plan has no included credits.
  sig { params(checkout: Copilot::CheckoutContext).returns(String) }
  def upgrade_credit_summary_clause(checkout)
    return "" unless checkout.target_included_credits

    if checkout.current_overage&.cents.to_i > 0
      ", which covers your additional usage and unlocks up to #{checkout.formatted_target_included_credits} in included credits"
    else
      ", which unlocks up to #{checkout.formatted_target_included_credits} in included credits"
    end
  end

  private

  # Fetches the user's current spending info from billing-platform.
  # Uses GetCopilotSpendingInfo RPC via Copilot::QuotaDataHelper.
  sig { params(copilot_user: Copilot::User).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def fetch_spending_info(copilot_user)
    client = ::Billing::Platform::Api::Client.new
    Copilot::QuotaDataHelper.fetch_copilot_spending_info(client: client, copilot_user: copilot_user)
  rescue StandardError
    nil
  end

  # Returns the AIC entitlement for a target product key using Copilot::Quotas::CFI_INCLUDED_AIC.
  sig { params(product_key: String).returns(T.nilable(Integer)) }
  def resolve_entitlement_for_product(product_key)
    plan_sym = case product_key
    when Copilot::INDIVIDUAL_PRO_PRODUCT_KEY then :pro
    when Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY then :pro_plus
    when Copilot::INDIVIDUAL_MAX_PRODUCT_KEY then :max
    end
    plan_sym ? Copilot::Quotas::CFI_INCLUDED_AIC[plan_sym] : nil
  end

  # Returns the price delta (in Money) for upgrading from the user's current plan to the target product, or nil if no upgrade.
  sig { params(copilot_user: Copilot::User, target_product_key: String).returns(T.nilable(Billing::Money)) }
  def compute_upgrade_price(copilot_user, target_product_key)
    return nil unless copilot_user.has_active_subscription?

    current_price = case
    when copilot_user.has_educational_access? then Copilot::COPILOT_EDU_MONTHLY_BASE_PRICE
    when copilot_user.has_max_access? then Copilot::COPILOT_MAX_MONTHLY_BASE_PRICE
    when copilot_user.has_pro_plus_access? then Copilot::COPILOT_PRO_PLUS_MONTHLY_BASE_PRICE
    when copilot_user.has_pro_access? then Copilot::COPILOT_PRO_MONTHLY_BASE_PRICE
    end

    target_price = case target_product_key
    when Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY then Copilot::COPILOT_PRO_PLUS_MONTHLY_BASE_PRICE
    when Copilot::INDIVIDUAL_MAX_PRODUCT_KEY then Copilot::COPILOT_MAX_MONTHLY_BASE_PRICE
    end

    return nil unless current_price && target_price && target_price > current_price

    Billing::Money.new((target_price - current_price) * 100)
  end

  sig { params(product_key: String, billing_cycle: String).returns(T.nilable(Billing::ProductUUID)) }
  def find_copilot_product_uuid(product_key, billing_cycle = "monthly")
    cycle = billing_cycle == "monthly" ? "month" : "year"
    Billing::ProductUUID.find_by(
      product_type: Copilot::PRODUCT_TYPE,
      product_key: product_key,
      billing_cycle: cycle
    )
  end

  sig { params(product_uuid: Billing::ProductUUID, coupon: Coupon).returns(Billing::Pricing) }
  def build_pricing_with_coupon(product_uuid, coupon)
    hypothetical_item = Billing::SubscriptionItem.new(
      subscribable: product_uuid,
      quantity: 1
    )

    Billing::Pricing.new(
      plan: GitHub::Plan.free,
      plan_duration: product_uuid.billing_cycle == "month" ? "month" : "year",
      coupon: coupon,
      subscription_items: [hypothetical_item],
      include_addons: true
    )
  end

  sig do
    params(
      pricing: Billing::Pricing,
      coupon: Coupon,
      billing_cycle: String
    ).returns(Billing::PricingDisplay::PricingData)
  end
  def build_pricing_data_from_billing_pricing(pricing, coupon, billing_cycle = "monthly")
    Billing::PricingDisplay::PricingData.new(
      original_price: pricing.discountable,
      discounted_price: pricing.discounted,
      discount_amount: pricing.discount,
      has_coupon: true,
      coupon: coupon,
      billing_cycle: billing_cycle,
      is_percentage_discount: coupon.percentage?,
      discount_percentage: coupon.percentage? ? (coupon.discount * 100).to_i : nil
    )
  end

  sig { params(product_uuid: T.nilable(Billing::ProductUUID), billing_cycle: String).returns(Billing::PricingDisplay::PricingData) }
  def build_pricing_data_without_coupon(product_uuid, billing_cycle = "monthly")
    price = product_uuid ? product_uuid.base_price : Billing::Money.new(0)

    Billing::PricingDisplay::PricingData.new(
      original_price: price,
      discounted_price: price,
      discount_amount: Billing::Money.new(0),
      has_coupon: false,
      coupon: nil,
      billing_cycle: billing_cycle,
      is_percentage_discount: false,
      discount_percentage: nil
    )
  end
end
