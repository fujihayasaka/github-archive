# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class Billing::Zuora::SyncMeteredProductUuidsFromZuoraJob < ApplicationJob
  queue_as :zuora

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  T.unsafe(self).retry_on(*::Billing::Zuora::RETRYABLE_ERRORS)

  def perform(zuora_products:)
    zuora_products.each do |zuora_product|
      sync_product_uuids(**zuora_product)
    end
  end

  private

  sig do
    params(
      zuora_product_id: String,
      product_type: String,
      zuora_product_rate_plans: T::Array[Hash],
    ).void
  end
  def sync_product_uuids(zuora_product_id:, product_type:, zuora_product_rate_plans:)
    zuora_product_rate_plans_zuorest = GitHub.zuorest_client.get_product_rate_plan(zuora_product_id)
    zuora_product_rate_plans = zuora_product_rate_plans.filter { |zprp| zprp[:effective_on] > Date.today }
    zuora_product_rate_plan_ids = zuora_product_rate_plans.map { |zprp| zprp[:zuora_product_rate_plan_id] }
    rate_plans_to_sync = zuora_product_rate_plans_zuorest["productRatePlans"].filter { |prp| zuora_product_rate_plan_ids.include?(prp["id"]) }
    with_write do
      rate_plans_to_sync.each do |zuora_product_rate_plan|
        zuora_product_rate_plan_charges = zuora_product_rate_plan["productRatePlanCharges"]
        zuora_product_rate_plan_id = zuora_product_rate_plan["id"]
        next unless should_sync_product?(zuora_product_rate_plan_id, zuora_product_rate_plan_charges)

        billing_cycle = :month

        Billing::ProductUUID.create!({
          product_key: zuora_product_rate_plan["name"],
          product_type: product_type,
          zuora_product_rate_plan_id: zuora_product_rate_plan_id,
          billing_cycle: billing_cycle,
          metered: true,
          name: zuora_product_rate_plan["name"],
          zuora_product_id: zuora_product_id,
          # transform zuora product rate plan charges to a hash that maps charge name to charge id
          # { "snakecase_charge_name": "charge_id" }
          zuora_product_rate_plan_charge_ids: zuora_product_rate_plan_charges.to_h do |zrpc|
            [zrpc["name"].underscore.parameterize(separator: "_").to_sym, zrpc["id"]]
          end,
          charges: zuora_product_rate_plan_charges.map do |zrpc|
            charge_model = zrpc["model"].underscore

            if charge_model == "per_unit"
              price = zrpc["pricing"][0]["price"]
            elsif charge_model == "overage"
              price = zrpc["pricing"][0]["overagePrice"]
            end

            Billing::ProductUUID::Charge.new(
              billing_duration: billing_cycle,
              name: zrpc["name"],
              price: price,
              type: charge_model,
              zuora_product_rate_plan_charge_id: zrpc["id"],
            )
          end
        })
      end
    end
  end

  def should_sync_product?(zuora_product_rate_plan_id, zuora_product_rate_plan_charges)
    # Only want to sync Zuora products where all rate plan charges are metered usage,
    # so charge model must be either PerUnit or Overage and billing period must be monthly.
    !Billing::ProductUUID.exists?(zuora_product_rate_plan_id: zuora_product_rate_plan_id) &&
    zuora_product_rate_plan_charges.all? { |zrpc| %w[PerUnit Overage].include?(zrpc["model"]) } &&
    zuora_product_rate_plan_charges.all? { |zrpc| zrpc["billingPeriod"] == "Month" }
  end
end
