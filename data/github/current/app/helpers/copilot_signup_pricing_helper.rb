# typed: strict
# frozen_string_literal: true

# Helper for calculating Copilot signup pricing with coupon support.
# Uses Billing::Pricing for consistent discount calculations across all signup pages.
module CopilotSignupPricingHelper
  sig do
    params(
      product_key: String,
      billing_cycle: String,
      user: User
    ).returns(Billing::PricingDisplay::PricingData)
  end
  def copilot_signup_pricing(product_key:, billing_cycle:, user:)
    product_uuid = find_copilot_product_uuid(product_key, billing_cycle)
    coupon = user.coupon_for_product(Copilot::PRODUCT_TYPE, product_key)

    if coupon && product_uuid
      pricing = build_pricing_with_coupon(product_uuid, coupon)
      build_pricing_data_from_billing_pricing(pricing, coupon, billing_cycle)
    else
      build_pricing_data_without_coupon(product_uuid, billing_cycle)
    end
  end

  private

  sig { params(product_key: String, billing_cycle: String).returns(T.nilable(Billing::ProductUUID)) }
  def find_copilot_product_uuid(product_key, billing_cycle)
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
  def build_pricing_data_from_billing_pricing(pricing, coupon, billing_cycle)
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
  def build_pricing_data_without_coupon(product_uuid, billing_cycle)
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
