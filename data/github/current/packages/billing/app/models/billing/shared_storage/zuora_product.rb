# typed: true
# frozen_string_literal: true

class Billing::SharedStorage::ZuoraProduct
  include Billing::ZuoraProduct::ZuoraSettings

  UNIT_OF_MEASURE = "Megabytes"

  # We are making the assumption that every month has 31 days instead of the average of ~30.5
  # days per year in order to never overcharge users.
  ASSUMED_MONTHLY_DAYS = 31
  ASSUMED_MONTHLY_HOURS = ASSUMED_MONTHLY_DAYS * 24
  MEGABYTES_IN_GIGABYTE = 1.gigabyte / Numeric::MEGABYTE

  # Price per monthly GB usage
  def self.unit_cost(account: nil, date: nil)
    mb_per_hour = ::Billing::MeteredProduct
      .effective_rate_plan_for(product: :shared_storage, sku: :default, account: account, date: date)
      .overage_price
    (mb_per_hour * MEGABYTES_IN_GIGABYTE * ASSUMED_MONTHLY_HOURS).round(2).to_s
  end

  def self.unit_cost_per_mb_in_cents(account: nil, date: nil)
    BigDecimal(unit_cost(account: account, date: date)) * 100 / MEGABYTES_IN_GIGABYTE
  end

  def self.uuid
    ::Billing::ProductUUID.find_by(product_type: product_type, product_key: product_key)
  end

  def self.product_name
    "GitHub Shared Storage"
  end

  def self.product_type
    "github.shared_storage"
  end

  def self.product_key
    "v0"
  end

  def self.sync_to_zuora
    new.sync_to_zuora
  end

  def sync_to_zuora
    return unless GitHub.billing_enabled?

    create_product
    create_rate_plans
  end

  private

  attr_reader :product_id

  def calculator
    @calculator ||= ::Billing::MeteredBilling::HourlyRateCalculator.new
  end

  def create_product
    result = GitHub.zuorest_client.create_product(
      {
        Name: self.class.product_name,
        EffectiveStartDate: GitHub::Billing.today.to_s,
        EffectiveEndDate: EFFECTIVE_END_DATE,
      },
    )
    @product_id = result["Id"]
  end

  def create_rate_plans
    return if Billing::ProductUUID.exists?(product_type: self.class.product_type, product_key: self.class.product_key)

    product_rate_plan = create_product_rate_plan
    product_rate_charges = create_product_rate_plan_charges(product_rate_plan)

    storage_rpc = product_rate_charges[0]
    price = calculator.hourly_unit_cost(
      cost_per_month: self.class.unit_cost,
      unit_divisor: 1024,
    ).to_f.to_s

    Billing::ProductUUID.create!(
      name: self.class.product_name,
      product_type: self.class.product_type,
      product_key: self.class.product_key,
      billing_cycle: :month,
      metered: true,
      zuora_product_id: product_id,
      zuora_product_rate_plan_id: product_rate_plan["Id"],
      zuora_product_rate_plan_charge_ids: {
        usage: storage_rpc["Id"],
      },
      charges: [
        Billing::ProductUUID::Charge.new(
          type: "overage",
          name: self.class.product_name,
          price: price.to_d,
          billing_duration: User::BillingDependency::MONTHLY_PLAN,
          zuora_product_rate_plan_charge_id: storage_rpc["Id"],
        )
      ]
    )
  end

  def create_product_rate_plan
    GitHub.zuorest_client.create_product_rate_plan(
      Name: "#{self.class.product_name} - #{self.class.product_key.titleize}",
      EffectiveStartDate: GitHub::Billing.today.to_s,
      EffectiveEndDate: EFFECTIVE_END_DATE,
      ProductId: product_id,
    )
  end

  def create_product_rate_plan_charges(product_rate_plan)
    GitHub.zuorest_client.create_action(
      type: "ProductRatePlanCharge",
      objects: [
        storage_rate_plan_charge(product_rate_plan_id: product_rate_plan["Id"]),
      ],
    )
  end

  def storage_rate_plan_charge(product_rate_plan_id:)
    price = calculator.hourly_unit_cost(
      cost_per_month: self.class.unit_cost,
      unit_divisor: 1024,
    ).to_f.to_s
    {
      BillingPeriod: "Month",
      ChargeModel: "Overage Pricing",
      ChargeType: "Usage",
      DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
      Name: "#{self.class.product_name} - #{self.class.product_type.titleize}",
      ProductRatePlanId: product_rate_plan_id,
      RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
      TaxCode: TAX_CODE,
      TaxMode: "TaxExclusive",
      Taxable: false,
      TriggerEvent: "ContractEffective",
      UOM: UNIT_OF_MEASURE,
      ListPrice: price,
      IncludedUnits: 0,
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            Currency: "USD",
            Price: price,
            PriceFormat: "Per Unit",
          },
        ],
      },
    }
  end
end
