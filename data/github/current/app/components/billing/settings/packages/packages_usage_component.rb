# typed: true
# frozen_string_literal: true

class Billing::Settings::Packages::PackagesUsageComponent < ApplicationComponent
  include GitHub::Memoizer

  PRODUCT_NAME = "packages"

  attr_reader :account, :spending_limit_enabled, :spending_limit_path

  def initialize(account:, spending_limit_enabled:, spending_limit_path: nil)
    @account = account
    @spending_limit_enabled = spending_limit_enabled
    @spending_limit_path = spending_limit_path
  end

  memoize def usage_for_skus
    usage_checker.usage_results_for(product: PRODUCT_NAME).compact
  end

  def entitlements
    usage_checker.entitlements_for(name: PRODUCT_NAME.capitalize)
  end

  def entitlements_used_percentage
    return 0 if entitlements.nil?
    ((entitlements.consumed_quantity / entitlements.allocated_quantity) * 100)
  end

  def exhausted_entitlements?
    usage_checker.exhausted_entitlement?(entitlements)
  end

  def total_charges
    return Billing::Money.new(0) if usage_for_skus.first.nil?
    Billing::Money.new(usage_checker.total_paid_usage_for(usages: usage_for_skus))
  end

  def budget
    usage_for_skus&.first&.budgets&.first
  end

  memoize def error_getting_usage?
    usage_checker.request_error? || usage_for_skus.empty? || usage_for_skus.first.nil?
  end

  def progress_bar_color
    entitlements_used_percentage <= 75 ? :accent_emphasis : :attention_emphasis
  end

  def account_total_quantity_consumed
    # account_consumed_quantity will be nil if the account is not an enterprise org
    return 0 unless enterprise_org?
    total = usage_for_skus.sum { |usage| usage.account_consumed_quantity }
    total.to_f / 1.gigabyte
  end

  def enterprise_org_entitlement_text
    enterprise_entitlements_remaining = if entitlements.present?
      entitlements.allocated_quantity - entitlements.consumed_quantity
    else
      0
    end

    "Included quota is shared between all organizations in your enterprise. #{number_with_precision(account_total_quantity_consumed, precision: 2, delimiter: ",")} GB used by this"\
    " organization and #{number_with_precision(enterprise_entitlements_remaining, precision: 2, delimiter: ",")}"\
    " included GB left."
  end

  def enterprise_org?
    account&.delegate_billing_to_business? || false
  end

  private

  memoize def usage_checker
    Billing::UsageChecker.new(
      account: account,
      product_names: [PRODUCT_NAME],
      timeout: 5
    )
  end
end
