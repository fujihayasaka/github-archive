# typed: strict
# frozen_string_literal: true

module Billing
  module Actions
    class ZuoraProductSalesServe

      autoload :ZuoraSettings, "github/billing/zuora_product/zuora_settings"

      include GitHub::Billing::ZuoraProduct::ZuoraSettings

      # Public: Synchronize the Zuora product and rate plans to Zuora
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def self.sync_to_zuora
        new.sync_to_zuora
      end

      sig { returns(Billing::Actions::ZuoraProduct::ProductRatePlan) }
      def self.custom_runners_rate_plan_charge
        Billing::Actions::ZuoraProduct::ProductRatePlan.new(
          name: "GitHub Actions - Runners - Commercial",
          unit_of_measure:  Billing::Actions::ZuoraProduct::UOM,
          product_rate_plan_charges: [
            { name: "8-Core", unit_cost: 0.032, },
            { name: "16-Core", unit_cost: 0.064, },
            { name: "32-Core", unit_cost: 0.128, },
            { name: "64-Core", unit_cost: 0.256, },
            { name: "4-Core", unit_cost: 0.016, }
          ]
        )
      end

      # Public: Synchronize the Zuora product and rate plans to Zuora
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def sync_to_zuora
        return [] unless GitHub.billing_enabled?

        create_remote_zuora_product
        create_product_rate_plan_charges
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :product_id

      # Internal: Create or find the remote Zuora product
      sig { void }
      def create_remote_zuora_product
        product_name = "GitHub Actions - Commercial"

        creation_params = {
          Name: product_name,
          EffectiveStartDate: GitHub::Billing.today.to_s,
          EffectiveEndDate: EFFECTIVE_END_DATE,
        }

        @product_id ||= T.let(GitHub.zuorest_client.get_product_id_for_name(product_name) || GitHub.zuorest_client.create_product(creation_params)["Id"], T.nilable(String))
      end

      # Internal: Create the Zuora product rate plans and rate plan charges
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def create_product_rate_plan_charges
        remote_product_rate_plans = GitHub.zuorest_client.get_product_rate_plan(product_id)

        rate_plan_charge = Billing::Actions::ZuoraProductSalesServe.custom_runners_rate_plan_charge

        existing_product_rate_plan = remote_product_rate_plans["productRatePlans"].find { |rp| rp["name"] == rate_plan_charge.name }

        return [] if existing_product_rate_plan

        product_rate = GitHub.zuorest_client.create_product_rate_plan(
          Name: rate_plan_charge.name,
          ProductId: product_id,
        )

        objects = rate_plan_charge.product_rate_plan_charges.map do |rate_plan|
          {
            BillingPeriod: "Month",
            ChargeType: "Usage",
            DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
            Name: rate_plan[:name],
            ProductRatePlanId: product_rate["Id"],
            RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
            TaxCode: TAX_CODE,
            TaxMode: "TaxExclusive",
            Taxable: false,
            TriggerEvent: "ContractEffective",
            ChargeModel: "Overage Pricing",
            IncludedUnits: 0,
            UOM: rate_plan_charge.unit_of_measure,
            ListPrice: rate_plan[:unit_cost],
            ProductRatePlanChargeTierData: {
              ProductRatePlanChargeTier: [
                {
                  Currency: "USD",
                  Price: rate_plan[:unit_cost],
                  PriceFormat: "Per Unit",
                },
              ],
            },
          }
        end

        GitHub.zuorest_client.create_action(
          type: "ProductRatePlanCharge",
          objects: objects,
        )

        objects
      end
    end
  end
end
