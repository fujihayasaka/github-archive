# typed: true
# frozen_string_literal: true

module Customers::Concerns::BillingPayload
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Kernel }

  sig do
    params(entity: ::Billing::Types::Account, plan_pricing: T.nilable(Billing::ProductPricing))
      .returns(T::Hash[Symbol, T.untyped])
  end
  def customer_payload(entity, plan_pricing: nil)
    customer = T.must(entity.customer)

    pending_cycle =
      case entity
      when Organization, User
        entity.pending_cycle(include_addons: false)
      when Business
        entity.pending_cycle
      end

    pending_plan = pending_cycle.plan
    pending_cycle_plan_name = pending_plan.entitlement_plan_name || pending_plan.name

    current_plan = entity.plan
    current_plan_name = current_plan.entitlement_plan_name || current_plan.name

    has_pending_plan_change = current_plan_name != pending_cycle_plan_name
    plan_duration = entity.plan_duration.downcase

    price_per_seat = case plan_duration
    when User::BillingDependency::YEARLY_PLAN
      current_plan.yearly_unit_cost
    else
      current_plan.unit_cost
    end

    on_trial = if entity.feature_flag_enabled?(:ghas_ghec_trial_billing_component, default: false)
      case entity
      when Business
        entity.has_active_advanced_security_trial? || entity.advanced_security_trial_enabled_for_entity?
      when Organization
        entity.has_active_advanced_security_trial?
      else
        false
      end
    else
      false
    end

    payload = {
      billingTarget: customer.billing_platform_billing_target,
      customerId: customer.id.to_i,
      customerType: entity.class.name.to_s,
      displayId: entity.display_login.to_s,
      name: entity.safe_profile_name.to_s,
      isVNextNative: customer.is_vnext_native?,
      plan: current_plan_name,
      planDuration: plan_duration,
      seats: pending_cycle.seats,
      pricePerSeat: BigDecimal(price_per_seat, 2),
      paymentAmount: BigDecimal(pending_cycle.payment_amount(use_balance: false).dollars),
      hasPendingPlanChange: has_pending_plan_change,
      onTrial: on_trial,
      hasDiscount: T.let(false, T::Boolean)
    }

    if plan_pricing
      payload[:planPrice] = plan_pricing.discounted_price.to_f
      payload[:hasDiscount] = plan_pricing.has_discount?
      if plan_pricing.has_discount?
        payload[:basePrice] = plan_pricing.base_price.to_f
        payload[:discountedPrice] = plan_pricing.discounted_price.to_f
        payload[:discountAmount] = plan_pricing.discount_amount.to_f
        payload[:isPercentageDiscount] = plan_pricing.percentage_discount?
        payload[:discountPercentage] = plan_pricing.discount_percentage
        payload[:couponWillExpire] = plan_pricing.coupon_will_expire?
        payload[:couponDurationLabel] = plan_pricing.coupon_duration_label
      end
    end

    payload
  end

  sig { params(subscription_item: T.nilable(Billing::Public::SubscriptionItem), product_pricing: T.nilable(Billing::ProductPricing)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def subscription_item_payload(subscription_item, product_pricing: nil)
    return nil unless subscription_item.present?
    has_pending_downgrade = subscription_item.pending_cancellation? ||
      (
        subscription_item.pending_change? &&
        T.must(subscription_item.pending_change_identifier).product_key != subscription_item.product_identifier.product_key
      )

    payload = {
      price: subscription_item.price.to_f,
      name: subscription_item.name,
      billingCycle: subscription_item.interval.to_s,
      hasPendingDowngrade: !!has_pending_downgrade,
      hasDiscount: T.let(false, T::Boolean)
    }

    if product_pricing&.has_discount?
      payload[:hasDiscount] = true
      payload[:basePrice] = product_pricing.base_price.to_f
      payload[:discountedPrice] = product_pricing.discounted_price.to_f
      payload[:discountAmount] = product_pricing.discount_amount.to_f
      payload[:isPercentageDiscount] = product_pricing.percentage_discount?
      payload[:discountPercentage] = product_pricing.discount_percentage
      payload[:couponWillExpire] = product_pricing.coupon_will_expire?
      payload[:couponDurationLabel] = product_pricing.coupon_duration_label
    end

    payload
  end
end
