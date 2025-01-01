# typed: true
# frozen_string_literal: true

class Businesses::Billing::BillingCycleComponent < ApplicationComponent

  attr_reader :this_business

  def initialize(this_business: nil)
    @this_business = this_business
  end

  def render?
    this_business
  end

  def yearly?
    this_business&.plan_duration == User::BillingDependency::YEARLY_PLAN
  end

  def plan_type
    yearly? ? "yearly" : "monthly"
  end

  def next_bill_date
    this_business&.billed_on&.strftime("%B %e, %Y")
  end

  def change_duration_path
    if this_business && yearly?
      billing_cycle_duration_change_enterprise_path(this_business, plan_duration: User::BillingDependency::MONTHLY_PLAN)
    elsif this_business
      billing_cycle_duration_change_enterprise_path(this_business, plan_duration: User::BillingDependency::YEARLY_PLAN)
    end
  end
end
