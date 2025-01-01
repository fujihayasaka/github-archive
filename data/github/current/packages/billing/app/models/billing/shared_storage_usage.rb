# typed: true
# frozen_string_literal: true

class Billing::SharedStorageUsage < Billing::BaseUsage
  HOURS_IN_DAY = 24
  HOURS_IN_ASSUMED_MONTH = Billing::SharedStorage::ZuoraProduct::ASSUMED_MONTHLY_DAYS * HOURS_IN_DAY

  def self.usage_quote(account)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner)
    instance.fetch_usage_quote
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

  def estimated_monthly_private_megabytes
    return if has_error?

    (private_megabyte_hours_used + estimated_remaining_private_megabyte_hours_used) / HOURS_IN_ASSUMED_MONTH
  end

  def estimated_monthly_total_megabytes(additional_megabytes: 0)
    return if has_error?

    estimated_monthly_private_megabytes + prorated_additional_megabytes(additional_megabytes)
  end

  def estimated_monthly_paid_megabytes(**args)
    return if has_error?

    [0, estimated_monthly_total_megabytes(**args) - plan_included_megabytes].max
  end

  def paid_usage_percentage
    return 100 if plan_included_megabytes.zero?
    return if has_error?

    percent = (estimated_monthly_paid_megabytes / Float(plan_included_megabytes)).round(3)
    (percent * 100).to_i
  end

  def included_usage_percentage
    return 100 if plan_included_megabytes.zero?
    return if has_error?

    percent = (estimated_monthly_private_megabytes / Float(plan_included_megabytes)).round(3)
    [(percent * 100).to_i, 100].min
  end

  def private_megabyte_hours_used
    return @private_megabyte_hours_used if defined?(@private_megabyte_hours_used)
    return if has_error?

    @private_megabyte_hours_used = (usage_effective_quantity.to_f / 1.megabyte).to_i
  end

  def plan_included_megabytes
    plan.shared_storage_included_megabytes
  end

  def latest_private_billable_stored_megabytes
    @latest_private_billable_stored_megabytes ||=
      ActiveRecord::Base.connected_to(role: :reading) do
        GitHub.dogstats.time("billing.shared_storage.current_usage.private_billable_stored_megabytes") do
          size_in_bytes = Billing::SharedStorage::CurrentUsage
            .for_reporting(billable_owner: billable_owner, owner_id: owner&.id)
            .sum(:aggregate_size_in_bytes)

          (size_in_bytes / 1.megabyte).to_i
        end
      end
  end

  def used_all_included_storage?
    estimated_monthly_private_megabytes >= plan_included_megabytes
  end

  def days_left_in_billing_cycle
    hours_left_in_billing_cycle / HOURS_IN_DAY
  end

  def prorated_additional_megabytes(additional_megabytes)
    (additional_megabytes * hours_left_in_billing_cycle).to_f / HOURS_IN_ASSUMED_MONTH
  end

  def fetch_usage_quote
    proposed_usage = [
      {
        product_name: :shared_storage,
        product_sku_name: :default,
        entitlement_quantity: plan_included_megabytes * 1.megabyte,
      },
    ]

    response = usage_quotes_api_call(proposed_usage)
    unless error_response?(response)
      proposed_private_usage_from_usage_quote_api!(response[:usage_quotes])
    end
  end

  def fetch_product_usage
    response = list_products_api_call(products: ["shared_storage"])
    unless error_response?(response)
      private_usage_from_product_list_api!(response[:product_usage])
    end
  end

  def fetch_accounts_usage(owner)
    response = list_accounts_api_call(products: ["shared_storage"])
    unless error_response?(response)
      accounts_usage = response[:account_usage]
      accounts_usage = accounts_usage.select { |usage| usage[:account][:account_id] == owner.id } if owner.present?
      products_usage = accounts_usage.map { |usage| usage[:product_usage] }.flatten

      private_usage_from_product_list_api!(products_usage)
    end
  end

  def additional_mb_hours_by_end_of_cycle(additional_megabytes: 0)
    (latest_private_billable_stored_megabytes + additional_megabytes) * hours_left_in_billing_cycle
  end

  private

  def proposed_private_usage_from_usage_quote_api!(usage_quotes)
    shared_storage_quote = usage_quotes.detect(&:shared_storage?)
    return if shared_storage_quote.nil?
    @usage_effective_quantity = shared_storage_quote[:total_proposed_usage][:effective_quantity]
    @usage_billable_quantity = shared_storage_quote[:total_proposed_usage][:billable_quantity]
    @usage_estimated_cost = shared_storage_quote[:total_proposed_usage][:estimated_cost]
  end

  def private_usage_from_product_list_api!(products_usage)
    sku_usage = aggregate_by_sku_usage(products_usage, product: "shared_storage")

    @usage_effective_quantity = sku_usage["default"][:effective_quantity]
    @usage_billable_quantity = sku_usage["default"][:billable_quantity]
    @usage_estimated_cost = sku_usage["default"][:estimated_cost]
  end

  def estimated_remaining_private_megabyte_hours_used
    latest_private_billable_stored_megabytes * hours_left_in_billing_cycle
  end

  def hours_left_in_billing_cycle
    HOURS_IN_ASSUMED_MONTH - hours_into_billing_cycle
  end

  def hours_into_billing_cycle
    diff = (GitHub::Billing.now - T.cast(billable_owner.current_metered_billing_cycle_starts_at, Time))
    (diff / 1.hour).to_i
  end

  attr_reader :usage_effective_quantity
end
