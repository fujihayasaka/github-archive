# typed: true
# frozen_string_literal: true

class Billing::Settings::CopilotForBusiness::UsageBodyComponent < ApplicationComponent
  def initialize(
    account:,
    copilot_monthly_usage: nil,
    show_spending: false,
    as_placeholder: false
  )
    @account = account
    @copilot_monthly_usage = copilot_monthly_usage
    @show_spending = show_spending
    @as_placeholder = as_placeholder
  end

  def has_copilot_monthly_usage?
    return false if @copilot_monthly_usage.nil?
    !@copilot_monthly_usage.is_a?(Billing::Api::ClientWrapper::BillingClientError)
  end

  def show_spending?
    @show_spending
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

  def copilot_for_business_usage
    return unless has_copilot_monthly_usage?
    @copilot_monthly_usage[:product_usage].select do |product_usage|
      product_usage[:product_sku][:name].include?("copilot_for_business")
    end
  end

  def copilot_effective_monthly_usage
    return unless has_copilot_monthly_usage?
    copilot_for_business_usage.sum { |product_usage| product_usage[:usage][:effective_quantity] }.round(4)
  end

  def copilot_total_monthly_cost
    return unless has_copilot_monthly_usage?
    copilot_for_business_usage.sum { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }
  end

  def total_copilot_cost
    Billing::Money.new(copilot_total_monthly_cost).format(no_cents_if_whole: false)
  end

  def sku_name
    copilot_organization.copilot_plan_business? ? ::Copilot::BUSINESS_PRODUCT_NAME : ::Copilot::ENTERPRISE_PRODUCT_NAME
  end
end
