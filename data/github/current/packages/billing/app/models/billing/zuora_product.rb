# typed: strict
# frozen_string_literal: true

class Billing::ZuoraProduct
  include ZuoraSettings

  PERCENTAGE_TYPES = T.let([:percentage_discount, :annual_discount].freeze, T::Array[Symbol])

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  attr_reader :charges
  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  attr_reader :custom_product_params
  sig { returns(T::Boolean) }
  attr_reader :couponable
  sig { returns(T::Boolean) }
  attr_reader :metered
  sig { returns(String) }
  attr_reader :product_key
  sig { returns(String) }
  attr_reader :product_name
  sig { returns(String) }
  attr_reader :product_type
  sig { returns(T.nilable(String)) }
  attr_reader :rate_plan_name
  sig { returns(T::Array[String]) }
  attr_reader :billing_frequencies

  # Creates a new metered/usage-based Zuora product with a single monthly billing cycle.
  #
  # This provides a simplified interface for creating metered products that aligns with
  # existing patterns used by Codespaces, Actions, and Shared Storage products.
  #
  # Metered products differ from recurring products:
  #   - ChargeType is "Usage" instead of "Recurring"
  #   - ChargeModel is "Per Unit Pricing"
  #   - Rate plan and charge names do not include a billing interval suffix
  #   - Only monthly billing frequency is supported
  #
  # * charges Array of Hash
  #   * type Symbol - identifier key for the charge (e.g. :unit, :compute, :storage)
  #   * unit String - unit of measure (e.g. "Usage Charge", "Hours")
  #   * prices Hash - must include :month key (e.g. { month: 1 })
  #   * name String (optional) - custom charge name, defaults to product_name
  # * rate_plan_name String (optional) - custom rate plan name, defaults to product_name.
  #     Use this when creating multiple rate plans under a single Zuora product (e.g. Actions).
  sig do
    params(
      charges: T::Array[T::Hash[Symbol, T.untyped]],
      product_name: String,
      product_type: String,
      product_key: String,
      rate_plan_name: T.nilable(String),
      custom_product_params: T::Hash[T.any(String, Symbol), T.untyped],
    ).void
  end
  def self.create_metered(charges:, product_name:, product_type:, product_key:, rate_plan_name: nil, custom_product_params: {})
    charges.each do |charge|
      raise ArgumentError, "Metered charges must include a :type" unless charge[:type].present?
      raise ArgumentError, "Metered charges must include a :unit" unless charge[:unit].present?
      raise ArgumentError, "Metered charges must include :month in :prices" unless charge.dig(:prices, :month)
    end

    create(
      charges: charges,
      product_name: product_name,
      product_type: product_type,
      product_key: product_key,
      rate_plan_name: rate_plan_name,
      custom_product_params: custom_product_params,
      couponable: false,
      metered: true,
      billing_frequencies: [User::BillingDependency::MONTHLY_PLAN],
    )
  end

  # Creates a new Zuora product for all User plan durations (yearly, monthly)
  #
  # * charges Array of Hash
  #   * type Array of Symbol [annual_discount, discount, unit, flat, nil] nil defaults to flat fee
  sig do
    params(
      charges: T::Array[T::Hash[Symbol, T.untyped]],
      product_name: String,
      product_type: String,
      product_key: String,
      custom_product_params: T::Hash[T.any(String, Symbol), T.untyped],
      couponable: T::Boolean,
      metered: T::Boolean,
      rate_plan_name: T.nilable(String),
      billing_frequencies: T.nilable(T.any(T::Array[String], String))
    ).void
  end
  def self.create(charges:, product_name:, product_type:, product_key:, custom_product_params: {}, couponable: false, metered: false, rate_plan_name: nil, billing_frequencies: nil)
    new(
      charges: charges,
      product_name: product_name,
      product_type: product_type,
      product_key: product_key,
      custom_product_params: custom_product_params,
      couponable: couponable,
      metered: metered,
      rate_plan_name: rate_plan_name,
      billing_frequencies: billing_frequencies
    ).create
  end

  sig do
    params(
      charges: T::Array[T::Hash[Symbol, T.untyped]],
      product_name: String,
      product_type: String,
      product_key: String,
      custom_product_params: T::Hash[T.any(String, Symbol), T.untyped],
      couponable: T::Boolean,
      metered: T::Boolean,
      rate_plan_name: T.nilable(String),
      billing_frequencies: T.nilable(T.any(T::Array[String], String))
    ).void
  end
  def initialize(charges:, product_name:, product_type:, product_key:, custom_product_params: {}, couponable: false, metered: false, rate_plan_name: nil, billing_frequencies: nil)
    @existing_zuora_product_id = T.let(custom_product_params.delete(:existing_id), T.nilable(String))
    @charges = charges
    @custom_product_params = custom_product_params
    @couponable = couponable
    @metered = metered
    @rate_plan_name = T.let(rate_plan_name, T.nilable(String))
    @product_key = product_key
    @product_name = product_name
    @product_type = product_type
    @billing_frequencies = T.let(Array.wrap(billing_frequencies || User::BillingDependency::PLAN_DURATIONS), T::Array[String])
  end

  # Public: Creates ProductUUID records for each type of billing cycle for a given product offering
  #
  # Reuses an existing Zuora Product if one already exists for one of the billing cycles, and doesn't create
  # duplicate records for a given product/cycle. Creates the Product, ProductRatePlan, and
  # ProductRatePlanCharges needed to represent a product offering in Zuora.
  #
  sig { void }
  def create
    return unless GitHub.billing_enabled?
    product_id = existing_product_id || create_product
    billing_frequencies.each do |billing_cycle|
      next if ::Billing::ProductUUID.find_by(product_type: product_type, product_key: product_key, billing_cycle: billing_cycle)
      params = {
        billing_cycle: billing_cycle,
        product_id: product_id,
        charges: charges,
        product_name: product_name,
        product_type: product_type,
        product_key: product_key,
        custom_product_params: custom_product_params,
        couponable: couponable,
        metered: metered,
        rate_plan_name: rate_plan_name,
      }

      Billing::CreateProductForBillingCycleJob.perform_now(params)
    end
  end

  sig { params(billing_cycle: String, product_id: String).returns(::Billing::ProductUUID) }
  def create_product_for_billing_cycle(billing_cycle, product_id)
    product_rate_plan = product_rate_plan_for(billing_cycle, product_id)
    product_charges = product_charges_for(billing_cycle, product_rate_plan)
    product_uuid_charges = product_uuid_charges_for(billing_cycle, product_charges)

    ::Billing::ProductUUID.create(
      name: product_name,
      product_type: product_type,
      product_key: product_key,
      billing_cycle: billing_cycle,
      zuora_product_id: product_id,
      zuora_product_rate_plan_id: product_rate_plan["Id"],
      zuora_product_rate_plan_charge_ids: convert_to_charge_ids(product_charges),
      charges: product_uuid_charges,
      couponable: couponable,
      metered: metered
    )
  end

  private

  # Private: Finds an existing ProductRatePlan by name on the Zuora product,
  # or creates a new one if none matches.
  #
  sig { params(billing_cycle: String, product_id: String).returns(T::Hash[String, T.untyped]) }
  def product_rate_plan_for(billing_cycle, product_id)
    zuora_product_rate_plans(product_id).find do |product_rate_plan|
      product_rate_plan["name"] == rate_plan_name_for(billing_cycle)
    end || create_product_rate_plan(billing_cycle, product_id)
  end

  # Private: Returns the ProductRatePlanCharges from an existing rate plan,
  # or creates them via the Zuora Action API if none exist yet.
  #
  sig { params(billing_cycle: String, product_rate_plan: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def product_charges_for(billing_cycle, product_rate_plan)
    product_charges = product_rate_plan["productRatePlanCharges"]
    return product_charges if product_charges.present?

    create_action_for_product(billing_cycle, product_rate_plan)
  end

  # Private: Maps Zuora charges to local ProductUUID::Charge objects,
  # skipping any entries where the Zuora charge ID is missing.
  #
  sig { params(billing_cycle: String, product_charges: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[::Billing::ProductUUID::Charge]) }
  def product_uuid_charges_for(billing_cycle, product_charges)
    charges.each_with_index.filter_map do |charge, index|
      next unless zuora_charge_id = product_charges.dig(index, "Id")
      build_product_uuid_charge(charge, billing_cycle, zuora_charge_id)
    end
  end

  # Private: Builds a ProductUUID::Charge from a charge definition hash and its corresponding
  # Zuora charge ID. Metered charges use the per-charge or product name directly, while recurring
  # charges append the billing cycle to the name.
  #
  sig do
    params(
      charge: T::Hash[Symbol, T.untyped],
      billing_cycle: String,
      zuora_charge_id: String,
    ).returns(::Billing::ProductUUID::Charge)
  end
  def build_product_uuid_charge(charge, billing_cycle, zuora_charge_id)
    ::Billing::ProductUUID::Charge.new(
      type: charge[:type],
      unit_of_measure: charge[:unit],
      billing_duration: billing_cycle,
      price: charge[:prices][billing_cycle.to_sym],
      zuora_product_rate_plan_charge_id: zuora_charge_id,
      name: metered ? (charge[:name].presence || product_name) : "#{product_name} - #{billing_cycle}",
      prorate: charge[:prorate] && charge[:prorate][billing_cycle.to_sym],
      advance_payment_on_upgrade: charge[:advance_payment_on_upgrade] && charge[:advance_payment_on_upgrade][billing_cycle.to_sym],
    )
  end

  sig { params(product_id: String).returns(T::Array[T::Hash[String, T.untyped]]) }
  def zuora_product_rate_plans(product_id)
    GitHub.zuorest_client.get_product_rate_plan(product_id)["productRatePlans"]
  end

  sig { params(billing_cycle: String, product_id: String).returns(T::Hash[String, T.untyped]) }
  def create_product_rate_plan(billing_cycle, product_id)
    GitHub.zuorest_client.create_product_rate_plan(zuora_product_rate_plan_params(billing_cycle, product_id))
  end

  sig do
    params(billing_cycle: String, product_rate_plan: T::Hash[String, T.untyped])
      .returns(T::Array[T::Hash[String, T.untyped]])
  end
  def create_action_for_product(billing_cycle, product_rate_plan)
    GitHub.zuorest_client.create_action(zuora_product_rate_plan_charge_params(billing_cycle, product_rate_plan["Id"]), custom_charge_headers)
  end

  sig { returns(String) }
  def create_product
    GitHub.zuorest_client.create_product(zuora_product_params)["Id"]
  end

  # Private: Add custom headers to a request
  #
  sig { returns(T::Hash[String, String]) }
  def custom_charge_headers
    if charges.any? { |charge| charge[:type].to_s.include?("discount") }
      { "X-Zuora-WSDL-Version" => DISCOUNT_WSDL_VERSION.to_s }
    else
      {}
    end
  end

  # Private: Check if a product already exists from a manual import or previously failed sync
  #
  sig { returns(T.nilable(String)) }
  def existing_product_id
    @existing_zuora_product_id.presence || ::Billing::ProductUUID.find_by(product_type: product_type, product_key: product_key)&.zuora_product_id
  end

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  def zuora_product_params
    {
      Name: product_name,
      EffectiveStartDate: GitHub::Billing.today.to_s,
      EffectiveEndDate: EFFECTIVE_END_DATE,
    }.merge(custom_product_params)
  end

  sig { params(billing_cycle: String, product_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def zuora_product_rate_plan_params(billing_cycle, product_id)
    {
      EffectiveStartDate: zuora_product_params[:EffectiveStartDate],
      EffectiveEndDate: EFFECTIVE_END_DATE,
      Name: rate_plan_name_for(billing_cycle),
      ProductId: product_id,
    }
  end

  # Private: Returns the rate plan name for a given billing cycle.
  # Uses the explicit rate_plan_name if set, otherwise defaults to product_name
  # for metered products or "product_name - billing_cycle" for recurring products.
  #
  sig { params(billing_cycle: String).returns(String) }
  def rate_plan_name_for(billing_cycle)
    rate_plan_name || (metered ? product_name : "#{product_name} - #{billing_cycle}")
  end

  sig { params(billing_cycle: String, rate_plan_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def zuora_product_rate_plan_charge_params(billing_cycle, rate_plan_id)
    defaults = if metered
      metered_charge_params(rate_plan_id)
    else
      recurring_charge_params(billing_cycle, rate_plan_id)
    end

    {
      type: "ProductRatePlanCharge",
      objects: charge_objects(billing_cycle).map do |obj|
        defaults.merge(obj)
      end
    }
  end

  # Private: Shared Zuora charge params common to both metered and recurring products.
  #
  sig { params(rate_plan_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def base_charge_params(rate_plan_id)
    {
      DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
      ProductRatePlanId: rate_plan_id,
      RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
      TaxCode: TAX_CODE,
      TaxMode: "TaxExclusive",
      Taxable: false,
      TriggerEvent: "ContractEffective",
    }
  end

  # Private: Zuora charge params for metered/usage-based products.
  # Uses ChargeType "Usage" with a monthly billing period.
  # Usage records are rated at end of billing period so all usage within
  # a cycle is aggregated before invoicing.
  # Bills on the 1st of every month (SpecificDayofMonth) regardless of the
  # customer account's BillCycleDay, so all metered products invoice on a
  # consistent calendar boundary.
  #
  sig { params(rate_plan_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def metered_charge_params(rate_plan_id)
    base_charge_params(rate_plan_id).merge(
      BillingPeriod: "Month",
      ChargeType: "Usage",
      Name: product_name,
      UsageRecordsRatingOption: "EndOfBillingPeriod",
      BillCycleType: "SpecificDayofMonth",
      BillCycleDay: 1,
    )
  end

  # Private: Zuora charge params for recurring (non-metered) products.
  # Uses ChargeType "Recurring" with billing period derived from the cycle (Annual or Month),
  # and includes billing period alignment for yearly subscriptions.
  #
  sig { params(billing_cycle: String, rate_plan_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def recurring_charge_params(billing_cycle, rate_plan_id)
    billing_period = billing_cycle == User::BillingDependency::YEARLY_PLAN ? "Annual" : "Month"
    base_charge_params(rate_plan_id).merge(
      BillingPeriod: billing_period,
      ChargeType: "Recurring",
      Name: "#{product_name} - #{billing_period}",
      **billing_period_alignment(billing_cycle),
    )
  end

  # Internal: For yearly subscriptions we want all charges to happen on the same
  # day. AlignToCharge is the default, and causes charges to occur on different dates,
  # depending on when the product was subscribed to.
  # ref: https://www.zuora.com/developer/api-reference/#operation/Object_POSTProductRatePlanCharge
  sig { params(billing_cycle: String).returns(T::Hash[Symbol, String]) }
  def billing_period_alignment(billing_cycle)
    return {} unless billing_cycle == User::BillingDependency::YEARLY_PLAN
    { BillingPeriodAlignment: "AlignToSubscriptionStart" }
  end

  # Private: Converts the simplified charge hash into the version Zuora expects for a flat fee or per unit
  # type of charge
  #
  sig { params(billing_cycle: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def charge_objects(billing_cycle)
    charges.map do |charge|
      if metered
        usage_charge(charge, billing_cycle.to_sym)
      elsif charge[:type] == :annual_discount
        annual_discount_charge(charge, billing_cycle.to_sym)
      elsif charge[:type].to_s.include?("discount")
        discount_charge(charge, billing_cycle.to_sym)
      elsif charge[:type].to_s.include?("unit")
        per_unit_charge(charge, billing_cycle.to_sym)
      elsif charge[:type].to_s == "flat"
        flat_fee_charge(charge, billing_cycle.to_sym)
      else
        flat_fee_charge(charge, billing_cycle.to_sym)
      end
    end.compact
  end

  # Private: Builds the Zuora charge params for a usage/metered charge.
  # Uses "Per Unit Pricing" model so billing platform submits usage at a per-unit rate.
  # Supports optional per-charge custom names to override the default product_name.
  #
  sig { params(charge: T::Hash[Symbol, T.untyped], billing_cycle: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def usage_charge(charge, billing_cycle)
    {
      ChargeModel: "Per Unit Pricing",
      DefaultQuantity: charge[:default_quantity] || 0,
      UOM: charge[:unit],
      Name: charge[:name].presence || product_name,
      ListPrice: charge[:prices][billing_cycle],
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            Currency: "USD",
            Price: charge[:prices][billing_cycle],
            PriceFormat: "Per Unit",
          },
        ],
      },
    }
  end

  # Private: Provides the parameters required to create a Discount in Zuora
  #
  sig { params(charge: T::Hash[Symbol, T.untyped], billing_cycle: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def discount_charge(charge, billing_cycle)
    discount_apply_details = charge[:product_discount_apply_product_target_uuids].select { |product| product.billing_cycle.to_s == billing_cycle.to_s }.map do |product|
      {
        AppliedProductRatePlanId: product.zuora_product_rate_plan_id,
      }
    end

    {
      ChargeModel: discount_charge_model(charge[:type]),
      ListPrice: charge[:prices][billing_cycle],
      ApplyDiscountTo: "RECURRING",
      DiscountLevel: "subscription",
      ProductDiscountApplyDetailData: {
        ProductDiscountApplyDetail: discount_apply_details,
      },
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            discount_rate_plan_charge_tier(charge[:type]) => charge[:prices][billing_cycle],
          },
        ],
      },
    }
  end

  sig { params(type: Symbol).returns(String) }
  def discount_charge_model(type)
    type == :percentage_discount ? "Discount-Percentage" : "Discount-Fixed Amount"
  end

  sig { params(type: Symbol).returns(Symbol) }
  def discount_rate_plan_charge_tier(type)
    type.in?(PERCENTAGE_TYPES) ? :DiscountPercentage : :DiscountAmount
  end

  sig { params(charge: T::Hash[Symbol, T.untyped], billing_cycle: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def flat_fee_charge(charge, billing_cycle)
    {
      ChargeModel: "Flat Fee Pricing",
      ListPrice: charge[:prices][billing_cycle],
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            Currency: "USD",
            Price: charge[:prices][billing_cycle],
            PriceFormat: "Flat Fee",
          },
        ],
      },
    }
  end

  sig { params(charge: T::Hash[Symbol, T.untyped], billing_cycle: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def per_unit_charge(charge, billing_cycle)
    {
      ChargeModel: "Per Unit Pricing",
      DefaultQuantity: charge[:default_quantity] || 0,
      ListPrice: charge[:prices][billing_cycle],
      UOM: charge[:unit],
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            Currency: "USD",
            Price: charge[:prices][billing_cycle],
            PriceFormat: "Per Unit",
          },
        ],
      },
    }
  end

  sig { params(charge: T::Hash[Symbol, T.untyped], billing_cycle: Symbol).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def annual_discount_charge(charge, billing_cycle)
    return if billing_cycle == :month

    {
      ChargeModel: "Discount-Percentage",
      ApplyDiscountTo: "RECURRING",
      DiscountLevel: "subscription",
      ListPrice: charge[:prices][billing_cycle],
      UOM: charge[:unit],
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            discount_rate_plan_charge_tier(charge[:type]) => charge[:prices][billing_cycle],
          },
        ],
      },
    }
  end

  # Private: Converts the ProductRatePlanChargeIds from Zuora into a hash for storing on the ProductUUID
  # record, e.g.
  #
  # { base_unit: "ChargeId", unit: "ChargeId" }
  #
  # product_charges: [{"Id" => "ChargeId"}, {"Id" => "ChargeId"}] - provided by Zuora API
  #
  sig { params(product_charges: T::Array[T::Hash[String, String]]).returns(T::Hash[String, String]) }
  def convert_to_charge_ids(product_charges)
    charges.each_with_index.each_with_object({}) do |(charge, index), charge_hash|
      product_charge = product_charges[index]
      next unless product_charge

      charge_hash[charge[:type]] = product_charge["Id"]
    end
  end
end
