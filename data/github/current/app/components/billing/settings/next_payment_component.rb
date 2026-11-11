# typed: true
# frozen_string_literal: true

class Billing::Settings::NextPaymentComponent < ApplicationComponent
  def initialize(target:, plan: nil, new_name_address_design: false)
    @target = target
    @plan = plan
    @new_name_address_design = new_name_address_design
  end

  private

  attr_reader :target, :plan

  def render?
    target.present? && !@new_name_address_design && GitHub.billing_enabled? && logged_in?
  end

  memoize def payment_amount
    target.payment_amount(plan: plan)
  end

  memoize def past_due?
    target.past_due?
  end

  memoize def coupon_expiration_time
    target.coupon_redemption.expires_at
  end

  memoize def next_charge_amount
    target.next_charge_amount
  end

  memoize def coupon
    target.coupon
  end
end
