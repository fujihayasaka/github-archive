# typed: true
# frozen_string_literal: true

class Billing::Settings::CopilotForBusiness::UsageBodyComponent < ApplicationComponent
  def initialize(
    account:,
    show_spending: false,
    as_placeholder: false,
    copilot_pricing: nil
  )
    @account = account
    @show_spending = show_spending
    @as_placeholder = as_placeholder
    @copilot_pricing = copilot_pricing
  end

  def show_spending?
    @show_spending
  end

  def has_copilot_monthly_usage?
    return false if @copilot_pricing.nil?
    show_spending?
  end

  def as_placeholder?
    @as_placeholder
  end

  memoize def copilot_organization
    Copilot::Organization.new(@account)
  end

  memoize def breakdown
    copilot_organization.billing_summary
  end

  memoize def free_trial_ends_at
    return unless copilot_organization.business_trial&.active?
    copilot_organization.business_trial.ends_at
  end

  def copilot_total_monthly_cost
    return unless has_copilot_monthly_usage?
    breakdown[:seats] * (@copilot_pricing[:price] * 100)
  end

  def total_copilot_cost
    Billing::Money.new(copilot_total_monthly_cost).format(no_cents_if_whole: false)
  end

  def sku_name
    copilot_organization.copilot_plan_business? ? ::Copilot::BUSINESS_PRODUCT_NAME : ::Copilot::ENTERPRISE_PRODUCT_NAME
  end
end
