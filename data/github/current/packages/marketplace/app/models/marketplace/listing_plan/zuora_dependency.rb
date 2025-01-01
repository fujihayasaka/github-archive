# typed: true
# frozen_string_literal: true

module Marketplace::ListingPlan::ZuoraDependency
  extend T::Helpers
  extend T::Sig
  requires_ancestor { Marketplace::ListingPlan }

  ZUORA_PRODUCT_CATEGORY = "marketplace"
  ZUORA_PRODUCT_TYPE = "marketplace.listing_plan"
  SPONSORSHIP_PRODUCT_CATEGORY = "sponsorships"

  sig { params(billing_cycle: T.any(String, Symbol)).returns(T.nilable(::Billing::ProductUUID)) }
  def product_uuid(billing_cycle)
    ::Billing::ProductUUID.find_by(product_type: ZUORA_PRODUCT_TYPE, product_key: id, billing_cycle: billing_cycle)
  end

  # Public: Returns the ProductRatePlanId for this plan and the given cycle in Zuora
  #
  # cycle: "year" or "month" - the billing cycle we want the zuora id for
  sig { params(cycle: T.any(String, Symbol)).returns(T.nilable(String)) }
  def zuora_id(cycle:)
    product_uuid(cycle)&.zuora_product_rate_plan_id
  end

  sig { params(cycle: T.any(String, Symbol)).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def zuora_charge_ids(cycle:)
    product_uuid(cycle)&.zuora_product_rate_plan_charge_ids
  end

  sig { params(cycle: T.any(String, Symbol)).returns(T.nilable(String)) }
  def zuora_product_id(cycle:)
    product_uuid(cycle)&.zuora_product_id
  end

  sig { returns String }
  def zuora_product_name
    "#{T.unsafe(listing).name}: #{name}"
  end

  # Public: the Zuora product rate plan ID for this plan's listing.
  #
  # Not currently supported for Marketplace subscriptions.
  sig { params(cycle: T.any(String, Symbol)).returns(NilClass) }
  def listing_product_rate_plan_id(cycle:)
    nil
  end

  # Public: the billing cycle for this plan.
  #
  # Not currently supported for Marketplace subscriptions.
  sig { returns NilClass }
  def billing_cycle
    nil
  end

  # Public: The charges tied to this plan that will be synced to Zuora
  # These charges differ based on a flat rate plan vs a per unit plan
  sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
  def zuora_charges
    per_unit? ? [per_unit_charge] : [flat_charge]
  end

  # Public: Syncs the plan to Zuora if its ProductUUID records don't exist, and will generate a ProductUUID
  # for each type of billing cycle
  #
  # Returns Array
  def sync_to_zuora
    GitHub::Billing::ZuoraProduct.create \
      product_type: ZUORA_PRODUCT_TYPE,
      product_key: id.to_s,
      product_name: zuora_product_name,
      charges: zuora_charges,
      custom_product_params: custom_product_params
  end

  # Public: Returns true if this listing_plan matches an invoice_item, i.e.
  # this listing_plan's listing name is part of the invoice_item's charge_name
  #
  # invoice_item        - A Billing::Zuora::InvoiceItem
  # match_copilot_cycle - Unused here. Only here for consistency with ProductUUID#match_invoice_item?
  #
  # Returns a Boolean
  def matches_invoice_item?(invoice_item, match_copilot_cycle: false)
    invoice_item.charge_name_include?(T.unsafe(listing).name)
  end

  private

  sig { returns T::Hash[Symbol, T.untyped] }
  def flat_charge
    {
      type: :flat,
      prices: { year: yearly_price_in_dollars, month: monthly_price_in_dollars },
    }
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def per_unit_charge
    {
      type: :unit,
      prices: { year: yearly_price_in_dollars, month: monthly_price_in_dollars },
      unit: "Seats",
    }
  end

  sig { returns T::Hash[Symbol, String] }
  def custom_product_params
    {
      ProductCategory__c: ZUORA_PRODUCT_CATEGORY,
      IntegratorName__c: T.unsafe(listing).name,
      IntegratorSlug__c: T.unsafe(listing).zuora_slug,
    }
  end
end
