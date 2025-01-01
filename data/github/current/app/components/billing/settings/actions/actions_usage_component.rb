# typed: true
# frozen_string_literal: true
class Billing::Settings::Actions::ActionsUsageComponent < ApplicationComponent
  include GitHub::Memoizer
  include Billing::Usage::Actions::ActionsHelper

  PRODUCT_NAME = "actions"

  attr_reader :account, :spending_limit_enabled, :spending_limit_path

  def initialize(
    account:,
    spending_limit_enabled:,
    spending_limit_path: nil,
    usage_moved_to_vnext: false,
    vnext_usage_link: ""
  )
    @account = account
    @spending_limit_enabled = spending_limit_enabled
    @spending_limit_path = spending_limit_path
    @usage_moved_to_vnext = usage_moved_to_vnext
    @vnext_usage_link = vnext_usage_link
  end

  memoize def usage_for_skus
    usage_checker.usage_results_for(product: PRODUCT_NAME).compact
  end

  memoize def custom_runtime_usages
    usages = usage_for_skus.select { |usage| usage.entitlement.nil? }
    usages.sort_by do |usage|
      runner_os = usage.name.split("_").first
      cores = usage.name[/\d+/].to_i
      [runner_os, cores]
    end
  end

  memoize def standard_runtime_usages
    usages = usage_for_skus.select { |usage| usage.entitlement.present? }
    usages.sort_by { |usage| sku_unit_price_with_multiplier(usage) }
  end

  def entitlements
    usage_checker.entitlements_for(name: PRODUCT_NAME.capitalize)
  end

  def entitlements_used_percentage
    return 0 if entitlements.nil?
    entitlements.consumed_percentage
  end

  def exhausted_entitlements?
    usage_checker.exhausted_entitlement?(entitlements)
  end

  def total_charges
    Billing::Money.new(usage_checker.total_paid_usage_for(usages: usage_for_skus))
  end

  # All SKUs currently use the same budget, so we can grab the first one.
  # If / when we enable more specific budgets, we'll need to update this.
  def budget
    usage_for_skus&.first&.budgets&.first
  end

  memoize def error_getting_usage?
    usage_checker.request_error? || usage_for_skus.empty?
  end

  def progress_bar_color
    entitlements_used_percentage <= 75 ? :accent_emphasis : :attention_emphasis
  end

  def documentation_url
    docs_path = "/billing/managing-billing-for-github-actions/about-billing-for-github-actions"
    GitHub.developer_help_url + docs_path
  end

  def entitlements_consumed_with_multiplier(sku)
    rate_plan_multiplier = get_rate_plan_multiplier(sku.name)
    number_with_precision(entitlements_consumed_quantity(sku) / rate_plan_multiplier, precision: 2, delimiter: ",")
  end

  def overages_consumed_with_multiplier(sku)
    rate_plan_multiplier = get_rate_plan_multiplier(sku.name)
    number_with_precision(overage_consumed_quantity(sku) / rate_plan_multiplier, precision: 2, delimiter: ",")
  end

  def sku_unit_price_with_multiplier(sku)
    rate_plan_multiplier = get_rate_plan_multiplier(sku.name)
    unit_price = sku.unit_price * rate_plan_multiplier
    number_with_precision(unit_price, precision: 3, strip_insignificant_zeros: true)
  end

  # for an enterprise managed organization, this is the total minutes consumed (both included and paid) for a standard runner SKU.
  # for all other account types, it's the total of only included or entitlement minutes consumed for a standard runner SKU.
  def entitlements_consumed_quantity(sku)
    if enterprise_org?
      sku.account_consumed_quantity
    else
      sku.entitlement_raw_quantity_consumed
    end
  end

  # for an enterprise managed organization, this quantity is the total minutes consumed for a custom runner SKU.
  # for all other account types, it's the amount of paid or overage minutes for any SKU, including standard runners.
  def overage_consumed_quantity(sku)
    if enterprise_org?
      sku.account_consumed_quantity
    else
      sku.overage_consumed_quantity
    end
  end

  def standard_sku_minutes_consumed_for_account
    # account_consumed_quantity will be nil unless the account is an enterprise managed org
    return 0 unless enterprise_org?
    standard_runtime_usages.sum { |usage| usage.account_consumed_quantity }
  end

  def standard_sku_total_overage_minutes_for_account
    # account_consumed_quantity will be nil unless the account is an enterprise managed org
    return 0 unless enterprise_org?
    allocated_quantity = entitlements&.allocated_quantity || 0
    [standard_sku_minutes_consumed_for_account - allocated_quantity, 0].max
  end

  def custom_sku_total_minutes_for_account
    return 0 unless enterprise_org?
    custom_runtime_usages.sum { |usage| usage.account_consumed_quantity }
  end

  def enterprise_org_entitlement_text
    enterprise_entitlements_remaining = if entitlements.present?
      entitlements.allocated_quantity - entitlements.consumed_quantity
    else
      0
    end

    "Included minutes quota is shared between all organizations in your enterprise."\
    " #{number_with_precision(standard_sku_minutes_consumed_for_account, precision: 2, delimiter: ",")} minutes used by this"\
    " organization and #{number_with_precision(enterprise_entitlements_remaining, precision: 2, delimiter: ",")}"\
    " included minutes left."
  end

  # Only standard runners can consume entitlement minutes. This method provides an explanation of how many
  # entitlement minutes each runner used with rate plan multipliers applied to help customers understand their usage.
  def entitlements_breakdown_text
    return enterprise_org_entitlement_text if enterprise_org?

    text = ""
    return text if entitlements.nil? || entitlements.consumed_quantity == 0

    skus_with_usage = standard_runtime_usages.select { |usage| usage.entitlement_raw_quantity_consumed > 0 }

    skus_with_usage.each do |usage|
      sku_text = "#{number_with_precision(usage.entitlement_raw_quantity_consumed, precision: 2, delimiter: ",")}"\
      " #{get_display_name(usage.name)} minutes"

      if skus_with_usage.size == 1
        text += "#{sku_text}."
      elsif usage == skus_with_usage.last
        text += "and #{sku_text}."
      else
        text += "#{sku_text}, "
      end
    end

    "Your #{number_with_precision(entitlements&.consumed_quantity, precision: 2, delimiter: ",")}"\
    " included minutes used consists of #{text}"
  end

  def enterprise_org?
    account.delegate_billing_to_business? || false
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
