# typed: true
# frozen_string_literal: true

class Billing::CodespacesUsage
  include GitHub::Memoizer

  PRODUCT_NAME = "codespaces"

  COMPUTE_ENTITLEMENTS_NAME = "Codespaces - Compute"
  STORAGE_ENTITLEMENTS_NAME = "Codespaces - Storage"
  ENTITLEMENTS = [COMPUTE_ENTITLEMENTS_NAME, STORAGE_ENTITLEMENTS_NAME]
  FAST_TIMEOUT_SECONDS = 5

  COMPUTE_SKUS = Billing::Api::ClientWrapper::CODESPACES_COMPUTE_SKUS.keys.map(&:to_s)
  STORAGE_SKUS = Billing::Api::ClientWrapper::CODESPACES_STORAGE_SKUS.keys.map(&:to_s)
  ALL_SKUS = Billing::Api::ClientWrapper::CODESPACES_SKUS.keys.map(&:to_s)

  attr_reader :usage_checker, :account

  def initialize(account:, fast_timeout: true)
    @account = account
    timeout = fast_timeout ? FAST_TIMEOUT_SECONDS : nil
    @usage_checker = Billing::UsageChecker.new(
      account: account,
      product_names: [PRODUCT_NAME],
      timeout: timeout,
    )
    # The meuse API requires the start time to be at the beginning of the day.
    # Lookback window is the last seven complete days.
    @lookback_end_at = Time.parse((DateTime.now.utc.at_beginning_of_day).to_s)
  end

  memoize def is_enterprise_org?
    usage_checker.is_enterprise_org
  end

  memoize def usage_allowed?
    compute_usage_allowed? && storage_usage_allowed?
  end

  memoize def prebuild_usage_allowed?
    storage_usage_allowed?
  end

  memoize def compute_usage_allowed?
    # codespace compute skus use the same entitlements, and all codespace skus
    # use the same budget, so we can pass any compute sku through.
    usage_checker.usage_available?(product: PRODUCT_NAME, sku: COMPUTE_SKUS.first)
  end

  memoize def storage_usage_allowed?
    # codespace storage skus use the same entitlements, and all codespace skus
    # use the same budget, so we can pass any storage sku through.
    usage_checker.usage_available?(product: PRODUCT_NAME, sku: STORAGE_SKUS.first)
  end


  memoize def budget_limit
    usage_checker.budget_limit(budgets: usages.flat_map(&:budgets).uniq)
  end

  memoize def spending_limit_percentage
    return 0 if total_paid_usage_cost.zero?
    percent = total_paid_usage_cost / Float(budget_limit).round(2)

    # If the usage limit is 0, but total usage is a non-zero we will get Infinity
    return 100 if percent == Float::INFINITY
    [(percent * 100).to_i, 100].min
  end

  # Total costs for the billable owner
  memoize def total_paid_usage_cost
    usage_checker.total_paid_usage_for(usages: usages)
  end

  # Total costs for the org account owned by an enterprise. Will be nil if not an enterprise org account.
  memoize def total_paid_usage_cost_for_enterprise_org_account
    usage_checker.total_paid_usage_for(usages: usages, account_specific_lookup: true)
  end

  # Total storage costs for the billable owner
  memoize def total_storage_paid_usage_cost
    usage_checker.total_paid_usage_for(usages: storage_usages)
  end

  # Total compute costs for the billable owner
  memoize def total_compute_paid_usage_cost
    usage_checker.total_paid_usage_for(usages: compute_usages)
  end

  # Total storage costs for the org account owned by an enterprise. Will be nil if not an enterprise org account.
  memoize def total_storage_paid_usage_cost_for_enterprise_org_account
    usage_checker.total_paid_usage_for(usages: storage_usages, account_specific_lookup: true)
  end

  # Total compute costs for the org account owned by an enterprise. Will be nil if not an enterprise org account.
  memoize def total_compute_paid_usage_cost_for_enterprise_org_account
    usage_checker.total_paid_usage_for(usages: compute_usages, account_specific_lookup: true)
  end

  # Quantity is in GB-months
  memoize def total_storage_paid_usage_quantity
    usage_checker.total_paid_usage_quantity_for(usages: storage_usages)
  end

  # Quantity is in hours
  memoize def total_compute_paid_usage_quantity
    usage_checker.total_paid_usage_quantity_for(usages: compute_usages)
  end

  memoize def compute_usages
    COMPUTE_SKUS.map { |sku| usage_checker.usage_for(product: PRODUCT_NAME, sku: sku) }.compact
  end

  memoize def storage_usages
    STORAGE_SKUS.map { |sku| usage_checker.usage_for(product: PRODUCT_NAME, sku: sku) }.compact
  end

  memoize def usages
    compute_usages + storage_usages
  end

  memoize def projected_usage
    return nil unless account.present?
    return nil unless seven_day_lookback_usage_breakdown.key?(:product_usage)
    seven_day_lookback_usage = seven_day_lookback_usage_breakdown[:product_usage].select do |product_usage|
      ALL_SKUS.include?(product_usage[:product_sku][:name]) && product_usage[:product][:name] == PRODUCT_NAME
    end
    # Expected response sample can be found in /test/test_helpers/billing/api/test_helpers.rb#client_response method
    # Today we expect & require these in the response:
    # {product_usage: {product: {name: "Codespaces"}, product_sku: {name: sku_name}, usage: {estimated_cost: {subunits: cost_in_cents}}}}
    seven_day_lookback = seven_day_lookback_usage.sum { |v| v[:usage][:estimated_cost][:subunits] }
    daily_average = seven_day_lookback / 7
    next_billing_start_date = account.billable_owner.next_metered_billing_cycle_starts_at
    days_remaining_in_pay_period = (next_billing_start_date.utc.at_beginning_of_day - @lookback_end_at) / 1.day

    # We want the cost for the org not the billable owner, which could be the entire enterprise bill
    total = is_enterprise_org? ? total_paid_usage_cost_for_enterprise_org_account : total_paid_usage_cost
    ((daily_average * days_remaining_in_pay_period.round(2)) + total).round
  end

  memoize def compute_entitlement
    usage_checker.entitlements_for(name: COMPUTE_ENTITLEMENTS_NAME)
  end

  memoize def storage_entitlement
    usage_checker.entitlements_for(name: STORAGE_ENTITLEMENTS_NAME)
  end

  memoize def has_entitlements?
    compute_entitlement.present? && storage_entitlement.present?
  end

  # Did the billable owner exhaust their entitlements and don't have spending limits set up?
  memoize def no_spending_limit_and_exhausted_entitlements?
    !has_spending_limit_set? && exhausted_all_entitlements?
  end

  # Does the billable owner have entitlements overages?
  memoize def has_entitlements_overages?
    exhausted_all_entitlements? && has_spending_limit_set?
  end

  # Did the billable owner exhaust their storage entitlements and don't have spending limits set up?
  memoize def no_spending_limit_and_exhausted_storage_entitlements?
    !has_spending_limit_set? && exhausted_storage_entitlements?
  end

  # Did the billable owner exhaust compute or storage entitlements
  # You need both entitlements to start/resume codespaces
  # Note that if there are no entitlements allocated to this account, this method will return false
  # - they can't exhaust entitlements they never had.
  memoize def exhausted_all_entitlements?
    exhausted_compute_entitlements? || exhausted_storage_entitlements?
  end

  # Note that if there are no storage entitlements allocated to this account, this method will return false
  # - they can't exhaust entitlements they never had.
  memoize def exhausted_storage_entitlements?
    usage_checker.exhausted_entitlement?(storage_entitlement)
  end

  # Note that if there are no compute entitlements allocated to this account, this method will return false
  # - they can't exhaust entitlements they never had.
  memoize def exhausted_compute_entitlements?
    usage_checker.exhausted_entitlement?(compute_entitlement)
  end

  # Has the billable owner set up a spending limit?
  memoize def has_spending_limit_set?
    usage_checker.has_spending_limit_set?(budgets: usages.flat_map(&:budgets))
  end

  # Has the billable owner set up an unlimited spending limit?
  memoize def has_unlimited_spending?
    usage_checker.unlimited_spending_limit_for?(budgets: usages.flat_map(&:budgets))
  end

  memoize def paid_overages_restricted_by_owner_payment_issue?
    usage_checker.paid_overages_restricted_by_owner_payment_issue?
  end

  memoize def seven_day_lookback_usage_breakdown
    start_at = @lookback_end_at - 7.days

    filters = {
      usage_ends_at: @lookback_end_at,
      product_names: [PRODUCT_NAME]
    }

    response = @usage_checker.client.list_product_usage(start_at, **filters)

    if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
      @request_error = true
      return {}
    end
    response
  end

  def request_error?
    usage_allowed? # ensure we make the request before checking if there was an error.
    usage_checker.request_error?
  end
end
