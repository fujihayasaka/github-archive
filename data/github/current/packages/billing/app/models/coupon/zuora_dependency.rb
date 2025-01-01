# typed: strict
# frozen_string_literal: true

module Coupon::ZuoraDependency
  extend T::Helpers

  requires_ancestor { Coupon }

  # Public: Returns the ProductRatePlanId for this plan and the given cycle in Zuora
  #
  # cycle: "year" or "month" - the billing cycle we want the zuora id for
  #
  sig { params(cycle: String).returns(String) }
  def zuora_id(cycle:)
    T.must(product_uuid(cycle)).zuora_product_rate_plan_id
  end

  # Public: the Billing::ProductUUID object for this plan
  #
  # This returns a Billing::ProductUUID record representing this plan's
  # Zuora Rate Plan ID and the Zuora plan's Product Rate Plan IDs
  sig { params(billing_cycle: String).returns(T.nilable(Billing::ProductUUID)) }
  def product_uuid(billing_cycle)
    ::Billing::ProductUUID.find_by(product_type: "github.coupon", product_key: product_key, billing_cycle: billing_cycle)
  end

  sig { params(cycle: String).returns(T::Hash[String, String]) }
  def zuora_charge_ids(cycle:)
    T.must(product_uuid(cycle)).zuora_product_rate_plan_charge_ids
  end

  # Public: Syncs the plan to Zuora if its ProductUUID records don't exist, and will generate a ProductUUID
  # for each type of billing cycle
  sig { void }
  def sync_to_zuora
    Billing::ZuoraProduct.create \
      product_type: "github.coupon",
      product_key: product_key,
      product_name: zuora_product_name,
      charges: zuora_charges
  end

  # Public: The charge type of this coupon. Either :fixed_discount or
  # :percentage_discount
  sig { returns(Symbol) }
  def zuora_charge_type
    T.must(zuora_charges.first)[:type]
  end

  sig { returns(String) }
  def zuora_product_name
    type = percentage? ? "Percentage" : "Fixed"
    "GitHub #{type} Discount"
  end

  private

  # Private: The product key for looking up the ProductUUID record
  sig { returns(String) }
  def product_key
    percentage? ? "percentage" : "fixed_amount"
  end

  # Private: The charges tied to this plan that will be synced to Zuora
  # These charges differ based on a percentage-off coupon vs a fixed-amount
  # coupon
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def zuora_charges
    percentage? ? [percentage_charge] : [fixed_amount_charge]
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def percentage_charge
    {
      type: :percentage_discount,
      prices: { year: zero_dollars, month: zero_dollars },
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def fixed_amount_charge
    {
      type: :fixed_discount,
      prices: { year: zero_dollars, month: zero_dollars },
    }
  end

  sig { returns(BigDecimal) }
  def zero_dollars
    Billing::Money.new(0).dollars
  end
end
