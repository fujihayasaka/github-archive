# typed: true
# frozen_string_literal: true

class Billing::PackageRegistry::ZuoraProduct
  include GitHub::Billing::ZuoraProduct::ZuoraSettings

  UOM = "Gigabytes"

  def self.unit_cost(account: nil, date: nil)
    GitHub::Billing::MeteredProduct
      .effective_rate_plan_for(product: :packages, sku: :default, account: account, date: date)
      .overage_price.to_s
  end

  def self.unit_cost_in_cents(account: nil, date: nil)
    BigDecimal(unit_cost(account: account, date: date)) * 100
  end

  def self.uuid
    Billing::ProductUUID.find_by(product_type: product_type, product_key: product_key)
  end

  def self.product_name
    "GitHub Package Registry"
  end

  def self.product_key
    "data transfer"
  end

  def self.product_type
    "github.package_registry"
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

    product_rate_plan = GitHub.zuorest_client.create_product_rate_plan(
      Name: "#{self.class.product_name} - #{self.class.product_key.titleize}",
      EffectiveStartDate: GitHub::Billing.today.to_s,
      EffectiveEndDate: EFFECTIVE_END_DATE,
      ProductId: product_id,
    )

    product_rate_charges = GitHub.zuorest_client.create_action(
      type: "ProductRatePlanCharge",
      objects: [
        bandwidth_rate_plan_charge(product_rate_plan_id: product_rate_plan["Id"]),
      ],
    )

    bandwidth_rpc = product_rate_charges[0]
    Billing::ProductUUID.create!(
      name: self.class.product_name,
      product_type: self.class.product_type,
      product_key: self.class.product_key,
      billing_cycle: :month,
      metered: true,
      zuora_product_id: product_id,
      zuora_product_rate_plan_id: product_rate_plan["Id"],
      zuora_product_rate_plan_charge_ids: {
        bandwidth: bandwidth_rpc["Id"],
      },
      charges: [
        Billing::ProductUUID::Charge.new(
          type: "overage",
          name: "#{self.class.product_name} - #{self.class.product_key.titleize}",
          price: self.class.unit_cost,
          billing_duration: :month,
          zuora_product_rate_plan_charge_id: bandwidth_rpc["Id"],
        )
      ]
    )
  end

  def bandwidth_rate_plan_charge(product_rate_plan_id:)
    {
      BillingPeriod: "Month",
      ChargeModel: "Overage Pricing",
      ChargeType: "Usage",
      IncludedUnits: 0,
      DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
      Name: "#{self.class.product_name} - #{self.class.product_key.titleize}",
      ProductRatePlanId: product_rate_plan_id,
      RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
      TaxCode: TAX_CODE,
      TaxMode: "TaxExclusive",
      Taxable: false,
      TriggerEvent: "ContractEffective",
      UOM: UOM,
      ListPrice: self.class.unit_cost,
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            Currency: "USD",
            Price: self.class.unit_cost,
            PriceFormat: "Per Unit",
          },
        ],
      },
    }
  end
end
