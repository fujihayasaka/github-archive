# typed: true
# frozen_string_literal: true

module Billing
  module Codespaces
    class ZuoraProduct
      include GitHub::Billing::ZuoraProduct::ZuoraSettings

      COMPUTE_UOM = "Hours"
      STORAGE_UOM = "Gigabyte Hours"
      PRICE_PER_GB_MONTH = 0.1

      # Price per hour of basic SKU
      COMPUTE_UNIT_COST = ::Codespaces::Skus::BASE_HOURLY_RATE.to_s
      COMPUTE_UNIT_COST_IN_CENTS = BigDecimal(COMPUTE_UNIT_COST) * 100

      # Public: Cost per Gigabyte hour of storage
      #
      # Return Float
      def self.storage_unit_cost
        calculator = ::Billing::MeteredBilling::HourlyRateCalculator.new

        calculator.hourly_unit_cost(
          cost_per_month: PRICE_PER_GB_MONTH,
        )
      end

      # Public: Cost per Gigabyte hour of storage in cents
      #
      # Return Float
      def self.storage_unit_cost_in_cents
        storage_unit_cost * 100
      end

      def self.product_name
        "GitHub Codespaces"
      end

      def self.product_type
        "github.codespaces"
      end

      def self.product_key
        "v0"
      end

      def self.uuid
        ::Billing::ProductUUID.find_by(product_type: product_type, product_key: product_key)
      end

      def self.sync_to_zuora
        new.sync_to_zuora
      end

      def sync_to_zuora
        return unless GitHub.billing_enabled?

        create_product
        create_rate_plan
      end

      private

      attr_reader :product_id

      def create_product
        response = GitHub.zuorest_client.create_product({
          Name: self.class.product_name,
          EffectiveStartDate: GitHub::Billing.today.to_s,
          EffectiveEndDate: EFFECTIVE_END_DATE,
        })

        @product_id = response["Id"]
      end

      def create_rate_plan
        return if Billing::ProductUUID.exists?(product_type: self.class.product_type, product_key: self.class.product_key)

        product_rate_plan = create_product_rate_plan
        product_rate_charges = create_product_rate_plan_charges(product_rate_plan)

        compute_usage_rpc = product_rate_charges[0]
        storage_usage_rpc = product_rate_charges[1]

        # TODO: This is no longer needed since Codepsaces v1 is managed from Codespaces/RatePlan
        Billing::ProductUUID.create!(
          product_type: self.class.product_type,
          product_key: self.class.product_key,
          billing_cycle: :month,
          zuora_product_id: product_id,
          zuora_product_rate_plan_id: product_rate_plan["Id"],
          zuora_product_rate_plan_charge_ids: {
            compute: compute_usage_rpc["Id"],
            storage: storage_usage_rpc["Id"]
          },
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
            compute_rate_plan_charge(product_rate_plan_id: product_rate_plan["Id"]),
            storage_rate_plan_charge(product_rate_plan_id: product_rate_plan["Id"])
          ]
        )
      end

      def compute_rate_plan_charge(product_rate_plan_id:)
        {
          BillingPeriod: "Month",
          ChargeType: "Usage",
          DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
          Name: "#{self.class.product_name} - Compute Usage",
          ProductRatePlanId: product_rate_plan_id,
          RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
          TaxCode: TAX_CODE,
          TaxMode: "TaxExclusive",
          Taxable: false,
          TriggerEvent: "ContractEffective",
          ChargeModel: "Overage Pricing",
          IncludedUnits: 0,
          UOM: COMPUTE_UOM,
          ProductRatePlanChargeTierData: {
            ProductRatePlanChargeTier: [
              {
                Currency: "USD",
                Price: COMPUTE_UNIT_COST,
                PriceFormat: "Per Unit",
              },
            ],
          },
        }
      end

      def storage_rate_plan_charge(product_rate_plan_id:)
        {
          BillingPeriod: "Month",
          ChargeType: "Usage",
          DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
          Name: "#{self.class.product_name} - Storage Usage",
          ProductRatePlanId: product_rate_plan_id,
          RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
          TaxCode: TAX_CODE,
          TaxMode: "TaxExclusive",
          Taxable: false,
          TriggerEvent: "ContractEffective",
          ChargeModel: "Overage Pricing",
          IncludedUnits: 0,
          UOM: STORAGE_UOM,
          ProductRatePlanChargeTierData: {
            ProductRatePlanChargeTier: [
              {
                Currency: "USD",
                Price: self.class.storage_unit_cost.to_f.to_s,
                PriceFormat: "Per Unit",
              },
            ],
          },
        }
      end
    end
  end
end
