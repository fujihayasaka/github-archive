# typed: strict
# frozen_string_literal: true

class Coupon::DiscountCalculator
  include GitHub::Memoizer

  sig { returns(Coupon) }
  attr_reader :coupon

  sig { returns(Billing::PlanSubscription) }
  attr_reader :plan_subscription

  sig { params(plan_subscription: Billing::PlanSubscription, coupon: Coupon).void }
  def initialize(plan_subscription, coupon)
    @plan_subscription = plan_subscription
    @coupon = coupon
  end

  # Whether the coupon is applicable to the current subscription.
  # Product-target coupons require an active subscription item for the targeted product.
  sig { returns(T::Boolean) }
  def applicable?
    return true unless coupon.has_product_target?

    !targeted_subscription_item.nil?
  end

  sig { returns(String) }
  def billing_interval
    if coupon.has_product_target? && (item = targeted_subscription_item)
      item.billing_interval
    else
      plan_subscription.plan_duration
    end
  end

  sig { returns(::Billing::Types::NonMoneyNumeric) }
  def discount_amount
    if coupon.percentage?
      coupon.discount * 100
    elsif coupon.has_product_target? && (item = targeted_subscription_item)
      coupon.discount * duration_multiplier(item)
    else
      coupon.discount * plan_subscription.plan_duration_in_months
    end
  end

  private

  sig { returns(T.nilable(Billing::SubscriptionItem)) }
  memoize def targeted_subscription_item
    return unless coupon.has_product_target?

    product_uuid = T.must(coupon.product_target_product_uuid)
    plan_subscription.active_subscription_to(
      product_type: product_uuid.product_type,
      product_key: product_uuid.product_key
    )
  end

  sig { params(item: Billing::SubscriptionItem).returns(Integer) }
  def duration_multiplier(item)
    item.monthly? ? 1 : 12
  end
end
