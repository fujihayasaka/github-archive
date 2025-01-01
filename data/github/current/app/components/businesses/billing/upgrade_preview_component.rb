# typed: true
# frozen_string_literal: true

class Businesses::Billing::UpgradePreviewComponent < ApplicationComponent
  def initialize(business:)
    @business = business
  end

  private

  attr_reader :business
  delegate :next_billing_date, to: :business

  def render?
    @business&.trial?
  end

  memoize def plan
    GitHub::Plan.business_plus(account: business)
  end

  def seats
    [business.total_consumed_licenses, 1].max
  end

  def subscription
    Billing::Subscription.for_account(business, seats: seats, plan: plan, duration_in_months: 1)
  end

  def total_upgrade_price
    subscription.plan_and_seat_cost
  end

  def per_seat_pricing
    Billing::PlanChange::PerSeatPricingModel.new(
      business,
      plan_duration: Business::BillingDependency::MONTHLY_PLAN,
      new_plan: plan,
      seats: seats,
      plan_effective_at: next_billing_date,
      plan_and_seat_cost_only: true,
    )
  end
end
