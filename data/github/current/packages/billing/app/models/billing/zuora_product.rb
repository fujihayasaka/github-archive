# typed: strict
# frozen_string_literal: true

class Billing::ZuoraProduct
  include ZuoraSettings

  PERCENTAGE_TYPES = T.let([:percentage_discount, :annual_discount].freeze, T::Array[Symbol])

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  attr_reader :charges
  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  attr_reader :custom_product_params
  sig { returns(String) }
  attr_reader :product_key
  sig { returns(String) }
  attr_reader :product_name
  sig { returns(String) }
  attr_reader :product_type
  sig { returns(T::Array[String]) }
  attr_reader :billing_frequencies

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
      billing_frequencies: T.nilable(T.any(T::Array[String], String))
    ).void
  end
  def self.create(charges:, product_name:, product_type:, product_key:, custom_product_params: {}, billing_frequencies: nil)
    new(
      charges: charges,
      product_name: product_name,
      product_type: product_type,
      product_key: product_key,
      custom_product_params: custom_product_params,
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
      billing_frequencies: T.nilable(T.any(T::Array[String], String))
    ).void
  end
  def initialize(charges:, product_name:, product_type:, product_key:, custom_product_params: {}, billing_frequencies: nil)
    @charges = charges
    @custom_product_params = custom_product_params
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
      }

      Billing::CreateProductForBillingCycleJob.perform_now(params)
    end
  end

  sig { params(billing_cycle: String, product_id: String).returns(::Billing::ProductUUID) }
  def create_product_for_billing_cycle(billing_cycle, product_id)
    product_rate_plan = zuora_product_rate_plans(product_id).find { |product_rate| product_rate["name"].match(/ - #{billing_cycle}\Z/) }
    unless product_rate_plan.present?
      product_rate_plan = create_product_rate_plan(billing_cycle, product_id)
    end

    product_charges = product_rate_plan["productRatePlanCharges"]
    product_charges = create_action_for_product(billing_cycle, product_rate_plan) unless product_charges.present?
    product_uuid_charges = charges.each_with_index.map do |charge, index|
      next unless product_charges[index]

      ::Billing::ProductUUID::Charge.new(
        type: charge[:type],
        unit_of_measure: charge[:unit],
        billing_duration: billing_cycle,
        price: charge[:prices][billing_cycle.to_sym],
        zuora_product_rate_plan_charge_id: product_charges[index]["Id"],
        name: "#{product_name} - #{billing_cycle}",
        prorate: charge[:prorate] && charge[:prorate][billing_cycle.to_sym],
      )
    end

    ::Billing::ProductUUID.create \
      name: product_name,
      product_type: product_type,
      product_key: product_key,
      billing_cycle: billing_cycle,
      zuora_product_id: product_id,
      zuora_product_rate_plan_id: product_rate_plan["Id"],
      zuora_product_rate_plan_charge_ids: convert_to_charge_ids(product_charges),
      charges: product_uuid_charges
  end

  private

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
    ::Billing::ProductUUID.find_by(product_type: product_type, product_key: product_key)&.zuora_product_id
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
      Name: "#{product_name} - #{billing_cycle}",
      ProductId: product_id,
    }
  end

  sig { params(billing_cycle: String, rate_plan_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def zuora_product_rate_plan_charge_params(billing_cycle, rate_plan_id)
    defaults = default_charge_params(billing_cycle, rate_plan_id)
    {
      type: "ProductRatePlanCharge",
      objects: charge_objects(billing_cycle).map do |obj|
        obj.merge(defaults)
      end
    }
  end

  # Internal: For yearly subscriptions we want all charges to happen on the same
  # day. AlignToCharge is the default, and causes charges to occur on different dates,
  # depending on when the product was subscribed to.
  # ref: https://www.zuora.com/developer/api-reference/#operation/Object_POSTProductRatePlanCharge
  sig { params(billing_cycle: String).returns(T::Hash[Symbol, String]) }
  def billing_period_alignment(billing_cycle)
    if billing_cycle == User::BillingDependency::YEARLY_PLAN
      { BillingPeriodAlignment: "AlignToSubscriptionStart" }
    else
      {}
    end
  end

  # Private: Provides the default parameters required to create each ProductRatePlanCharge in Zuora
  #
  # billing_cycle: ["year", "month"]
  # rate_plan_id: "productRatePlanId"
  #
  sig { params(billing_cycle: String, rate_plan_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def default_charge_params(billing_cycle, rate_plan_id)
    billing_period = billing_cycle == User::BillingDependency::YEARLY_PLAN ? "Annual" : "Month"
    {
      BillingPeriod: billing_period,
      ChargeType: "Recurring",
      DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
      Name: "#{product_name} - #{billing_period}",
      ProductRatePlanId: rate_plan_id,
      RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
      TaxCode: TAX_CODE,
      TaxMode: "TaxExclusive",
      Taxable: false,
      TriggerEvent: "ContractEffective",
      **billing_period_alignment(billing_cycle),
    }
  end

  # Private: Converts the simplified charge hash into the version Zuora expects for a flat fee or per unit
  # type of charge
  #
  sig { params(billing_cycle: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def charge_objects(billing_cycle)
    charges.map do |charge|
      if charge[:type] == :annual_discount
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

  # Private: Provides the parameters required to create a Discount in Zuora
  #
  sig { params(charge: T::Hash[Symbol, T.untyped], billing_cycle: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def discount_charge(charge, billing_cycle)
    {
      ChargeModel: discount_charge_model(charge[:type]),
      ListPrice: charge[:prices][billing_cycle],
      ApplyDiscountTo: "RECURRING",
      DiscountLevel: "subscription",
      ProductDiscountApplyDetailData: {
        ProductDiscountApplyDetail: applied_product_rate_plan_ids(billing_cycle),
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

  # Private: Zuora rate plan ids of products we should be applying discounts to
  # (i.e. GitHub Products)
  #
  sig { params(billing_cycle: Symbol).returns(T::Array[T::Hash[Symbol, String]]) }
  def applied_product_rate_plan_ids(billing_cycle)
    ::Billing::ProductUUID.discountable.for_billing_interval(billing_cycle).map do |product|
      {
        AppliedProductRatePlanId: product.zuora_product_rate_plan_id,
      }
    end
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
