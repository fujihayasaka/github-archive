# typed: true
# frozen_string_literal: true

class Businesses::OrderPreviewComponent < ApplicationComponent
  def initialize(business:, duration:, form_field: false, seats: nil)
    @business = business
    @duration = duration
    @form_field = form_field
    @seats = seats
  end

  attr_reader :business, :duration, :form_field, :seats

  delegate :changing_duration?,
    :price_difference,
    to: :plan_change

  delegate :plan,
    to: :business

  def next_billing_date
    return if metered_plan?

    if trial?
      business.trial_expires_at.to_date
    else
      business.billed_on
    end
  end

  def final_price(github_only: false)
    plan_change.final_price(github_only: github_only, use_balance: false)
  end

  def price_prorated?
    effective_immediately? && !trial? && !organization_upgrade_initiated?
  end

  def effective_immediately?
    return true if metered_plan?
    return true if trial?
    return true if organization_upgrade_initiated?
    return false if changing_duration?
    price_difference > 0
  end

  def renewal_list_price
    new_subscription.plan_and_seat_cost
  end

  def new_subscription
    plan = GitHub::Plan.business_plus(account: business)
    @new_subscription = Billing::Subscription.for_account business,
      seats: seats || business.seats,
      plan: plan,
      duration_in_months: duration_in_months
  end

  def monthly_plan?
    duration == User::BillingDependency::MONTHLY_PLAN
  end

  def yearly_plan?
    !monthly_plan?
  end

  memoize def metered_plan?
    business.metered_plan?
  end

  def duration_in_months
    monthly_plan? ? 1 : 12
  end

  memoize def trial?
    business.trial?
  end

  memoize def organization_upgrade_initiated?
    business.organization_upgrade_initiated?
  end

  memoize def plan_change
    plan = GitHub::Plan.business_plus(account: business)
    ::Billing::PlanChange::PerSeatPricingModel.new business,
      plan_duration: duration,
      new_plan: plan,
      seats: seats || business.seats,
      plan_effective_at: trial? ? next_billing_date : nil,
      plan_and_seat_cost_only: true
  end
end
