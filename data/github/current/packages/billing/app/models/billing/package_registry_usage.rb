# typed: true
# frozen_string_literal: true

class Billing::PackageRegistryUsage < Billing::BaseUsage
  def self.usage_quote(account, additional_gigabytes: 0)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner)
    instance.fetch_usage_quote(additional_gigabytes: additional_gigabytes)
    instance
  end

  def self.product_usage(account, shared_usage: nil)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner, shared_usage: shared_usage)
    instance.fetch_product_usage
    instance
  end

  def self.account_usage(account, shared_usage: nil)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner, shared_usage: shared_usage)
    instance.fetch_accounts_usage(owner)
    instance
  end

  def initialize(billable_owner, owner: nil, starts_at: nil, usage_quote: {}, shared_usage: nil)
    super(billable_owner, owner: owner, starts_at: nil, shared_usage: shared_usage)

    if usage_quote.present?
      proposed_private_usage_from_usage_quote_api!([usage_quote])
    end
  end

  def total_gigabytes_used
    return if has_error?
    private_gigabytes_used
  end

  def private_gigabytes_used
    return if has_error?
    unrounded_private_gigabytes_used.ceil
  end

  def unrounded_private_gigabytes_used
    return if has_error?
    usage_effective_quantity.to_f / 1.gigabyte
  end

  def billable_gigabytes
    return if has_error?

    [0, unrounded_private_gigabytes_used.ceil - plan_included_bandwidth].max
  end

  def paid_usage_percentage
    return 100 if plan_included_bandwidth.zero?
    return if has_error?
    (billable_gigabytes.to_f / plan_included_bandwidth) * 100
  end

  def included_usage_percentage
    return 100 if plan_included_bandwidth.zero?
    return if has_error?
    percent = (unrounded_private_gigabytes_used / Float(plan_included_bandwidth)).round(3)
    [(percent * 100).to_i, 100].min
  end

  def plan_included_bandwidth
    plan.package_registry_included_bandwidth
  end

  def fetch_usage_quote(additional_gigabytes: 0)
    proposed_usage = [
      {
        product_name: :packages,
        product_sku_name: :default,
        proposed_quantity: additional_gigabytes * 1.gigabyte,
        entitlement_quantity: plan_included_bandwidth * 1.gigabyte,
      },
    ]

    response = usage_quotes_api_call(proposed_usage)
    unless error_response?(response)
      proposed_private_usage_from_usage_quote_api!(response[:usage_quotes])
    end
  end

  def fetch_product_usage
    response = list_products_api_call(products: ["packages"])
    unless error_response?(response)
      private_usage_from_product_list_api!(response[:product_usage])
    end
  end

  def fetch_accounts_usage(owner)
    response = list_accounts_api_call(products: ["packages"])
    unless error_response?(response)
      accounts_usage = response[:account_usage]
      accounts_usage = accounts_usage.select { |usage| usage[:account][:account_id] == owner.id } if owner.present?
      products_usage = accounts_usage.map { |usage| usage[:product_usage] }.flatten

      private_usage_from_product_list_api!(products_usage)
    end
  end

  private

  def proposed_private_usage_from_usage_quote_api!(usage_quotes)
    packages_quote = usage_quotes.detect(&:packages?)
    @usage_effective_quantity = packages_quote[:total_proposed_usage][:effective_quantity]
    @usage_billable_quantity = packages_quote[:total_proposed_usage][:billable_quantity]
    @usage_estimated_cost = packages_quote[:total_proposed_usage][:estimated_cost]
  end

  def private_usage_from_product_list_api!(products_usage)
    sku_usage = aggregate_by_sku_usage(products_usage, product: "packages")

    @usage_effective_quantity = sku_usage["default"][:effective_quantity]
    @usage_billable_quantity = sku_usage["default"][:billable_quantity]
    @usage_estimated_cost = sku_usage["default"][:estimated_cost]
  end

  attr_reader :usage_effective_quantity
end
