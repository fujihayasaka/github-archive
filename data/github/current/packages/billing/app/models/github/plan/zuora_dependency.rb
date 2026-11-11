# typed: strict
# frozen_string_literal: true

module GitHub::Plan::ZuoraDependency
  extend T::Helpers

  ZUORA_PRODUCT_TYPE = "github.plan"

  requires_ancestor { GitHub::Plan }

  # Public: Returns the ProductRatePlanId for this plan and the given cycle in Zuora
  sig { params(cycle: T.any(Symbol, String)).returns(T.nilable(String)) }
  def zuora_id(cycle:)
    product_uuid(cycle)&.zuora_product_rate_plan_id
  end

  sig { params(cycle: T.any(Symbol, String)).returns(T.nilable(T::Hash[Symbol, String])) }
  def zuora_charge_ids(cycle:)
    product_uuid(cycle)&.zuora_product_rate_plan_charge_ids
  end

  # Public: Syncs the plan to Zuora if its ProductUUID records don't exist, and will generate a ProductUUID
  # for each type of billing cycle
  sig { void }
  def sync_to_zuora
    Billing::ZuoraProduct.create \
      product_type: ZUORA_PRODUCT_TYPE,
      product_key: name,
      product_name: zuora_product_name,
      charges: zuora_charges
  end

  # Public: the Billing::ProductUUID object for this plan
  #
  # This returns a Billing::ProductUUID record representing this plan's
  # Zuora Rate Plan ID and the Zuora plan's Product Rate Plan IDs
  sig { params(billing_cycle: T.any(Symbol, String)).returns(T.nilable(Billing::ProductUUID)) }
  def product_uuid(billing_cycle)
    ::Billing::ProductUUID.find_by(product_type: ZUORA_PRODUCT_TYPE, product_key: name, billing_cycle: billing_cycle)
  end

  # Public: Does this plan have separate base and unit costs?
  #
  # This is true for GitHub::Plan.business
  sig { returns(T::Boolean) }
  def base_cost?
    # This is not a great way to check this, so working around this for now
    return true if business?
    per_seat? && cost != unit_cost
  end

  sig { returns(String) }
  def zuora_product_name
    case display_name
    when "business cloud", "enterprise"
      "GitHub Enterprise Cloud"
    when "pro"
      "GitHub Developer Plan"
    else
      "GitHub #{display_name.titleize} Plan"
    end
  end

  private

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def zuora_charges
    per_seat? ? per_seat_charges : [flat_charge]
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def per_seat_charges
    [per_unit_charge].tap do |charges|
      charges << per_unit_base_charge if base_cost?
      charges << annual_discount_charge
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def flat_charge
    {
      type: :flat,
      prices: { year: yearly_cost, month: cost },
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def per_unit_base_charge
    {
      default_quantity: base_units,
      type: :base_unit,
      prices: { year: yearly_cost / base_units, month: cost / base_units },
      unit: "Seats",
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def per_unit_charge
    {
      type: :unit,
      prices: { year: yearly_unit_cost, month: unit_cost },
      unit: "Seats",
    }
  end

  # Annual discount default charge is 0, it exists only for Zuora yearly plan
  # This value is overridden if the account allowed_annual_discount? method returns true
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def annual_discount_charge
    {
      type: :annual_discount,
      prices: { year: 0 },
      unit: "Seats",
    }
  end
end
