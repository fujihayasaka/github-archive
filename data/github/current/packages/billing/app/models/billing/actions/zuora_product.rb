# typed: strict
# frozen_string_literal: true

module Billing
  module Actions
    # Encapsulates the Zuora product and rate plan properties for billing
    # for GitHub Actions usage
    class ZuoraProduct

      include Billing::ZuoraProduct::ZuoraSettings

      class ProductRatePlan

        include GitHub::Memoizer

        sig { returns(String) }
        attr_reader :name

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :product_rate_plan_charges

        sig { returns(String) }
        attr_reader :unit_of_measure

        sig do
          params(
            name: String,
            product_rate_plan_charges: T::Array[T::Hash[Symbol, T.untyped]],
            unit_of_measure: String
          ).void
        end
        def initialize(name:, product_rate_plan_charges:, unit_of_measure:)
          @name = name
          @product_rate_plan_charges = product_rate_plan_charges
          @unit_of_measure = unit_of_measure
        end

        sig { returns(Billing::ProductUUID) }
        memoize def product_uuid
          ::Billing::ProductUUID.find_by!(product_type: ::Billing::Actions::ZuoraProduct.product_type, product_key: name)
        end

        sig { returns(String) }
        def zuora_id
          product_uuid.zuora_product_rate_plan_id
        end

        sig { returns(T::Hash[Symbol, String]) }
        def zuora_charge_ids
          product_uuid.zuora_product_rate_plan_charge_ids
        end
      end

      UOM = "Minutes"

      sig { returns(String) }
      def self.product_type
        "github.actions"
      end

      sig { returns(ProductRatePlan) }
      def self.private_visibility_rate_plan_charge
        ProductRatePlan.new(
          name: "Private Repos Usage",
          unit_of_measure: UOM,
          product_rate_plan_charges: [
            { name: "GitHub Actions - Private Repos Usage", unit_cost: 0.008 },
          ]
        )
      end

      sig { returns(ProductRatePlan) }
      def self.custom_runners_rate_plan_charge
        ProductRatePlan.new(
          name: "GitHub Actions - Runners",
          unit_of_measure: UOM,
          product_rate_plan_charges: [
            { name: "GitHub Actions - 4 Core Usage", unit_cost: 0.016, },
            { name: "GitHub Actions - 8 Core Usage", unit_cost: 0.032, },
            { name: "GitHub Actions - 16 Core Usage", unit_cost: 0.064, },
            { name: "GitHub Actions - 32 Core Usage", unit_cost: 0.128, },
            { name: "GitHub Actions - 64 Core Usage", unit_cost: 0.256, }
          ]
        )
      end

      # Public: Actions unit cost
      sig { params(account: T.nilable(Billing::Types::Account), date: T.nilable(Date)).returns(String) }
      def self.unit_cost(account: nil, date: nil)
        ::Billing::MeteredProduct
          .effective_rate_plan_for(product: :actions, sku: :linux, account: account, date: date)
          .overage_price.to_s
      end

      # Public: Actions unit cost in cents
      sig { params(account: T.nilable(Billing::Types::Account), date: T.nilable(Date)).returns(BigDecimal) }
      def self.unit_cost_in_cents(account: nil, date: nil)
        BigDecimal(unit_cost(account: account, date: date)) * 100
      end

      # Public: List of rate plan charges that will be synchronized to zuora
      sig { returns(T::Array[ProductRatePlan]) }
      def self.rate_plan_charges
        [
          private_visibility_rate_plan_charge,
          custom_runners_rate_plan_charge,
        ]
      end

      # Public: Synchronize the Zuora product and rate plans to Zuora
      sig { void }
      def self.sync_to_zuora
        new.sync_to_zuora
      end

      # Public: Synchronize the Zuora product and rate plans to Zuora
      sig { void }
      def sync_to_zuora
        return unless GitHub.billing_enabled?

        create_remote_zuora_product
        create_product_rate_plan_charges
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :product_id

      # Internal: Create or find the remote Zuora product
      sig { void }
      def create_remote_zuora_product
        product_name = "GitHub Actions"

        creation_params = {
          Name: product_name,
          EffectiveStartDate: GitHub::Billing.today.to_s,
          EffectiveEndDate: EFFECTIVE_END_DATE,
        }

        @product_id ||= T.let(Billing::ProductUUID.find_by(product_type: self.class.product_type, product_key: "Private Repos Usage")&.zuora_product_id ||
          GitHub.zuorest_client.get_product_id_for_name(product_name) ||
          GitHub.zuorest_client.create_product(creation_params)["Id"], T.nilable(String))
      end

      sig { params(product_rate_charges: T::Array[T::Hash[String, T.untyped]]).returns(T::Hash[Symbol, String]) }
      def zuora_product_rate_plan_charge_ids(product_rate_charges:)
        charges = {}
        product_rate_charges.each do |product_rate_plan_charge|
          name = product_rate_plan_charge["name"] || product_rate_plan_charge["Name"]
          id = product_rate_plan_charge["id"] || product_rate_plan_charge["Id"]
          charge_id_key = name.underscore.parameterize(separator: "_").to_sym
          charges[charge_id_key] = id
        end
        charges
      end

      # Internal: Create the Zuora product rate plans and rate plan charges
      sig { void }
      def create_product_rate_plan_charges
        GitHub.zuorest_client.timeout = 60
        remote_product_rate_plans = GitHub.zuorest_client.get_product_rate_plan(product_id)

        self.class.rate_plan_charges.each do |rate_plan_charge|
          existing_product_rate_plan = remote_product_rate_plans["productRatePlans"].find { |rp| rp["name"] == rate_plan_charge.name }

          if existing_product_rate_plan
            next if Billing::ProductUUID.exists?(product_type: self.class.product_type, product_key: rate_plan_charge.name)

            Billing::ProductUUID.create!(
              product_type: self.class.product_type,
              product_key: rate_plan_charge.name,
              name: rate_plan_charge.name,
              billing_cycle: :month,
              metered: true,
              zuora_product_id: product_id,
              zuora_product_rate_plan_id: existing_product_rate_plan["id"],
              zuora_product_rate_plan_charge_ids: zuora_product_rate_plan_charge_ids(
                product_rate_charges: existing_product_rate_plan["productRatePlanCharges"]
              ),
              charges: existing_product_rate_plan["productRatePlanCharges"].map do |rate_plan|
                Billing::ProductUUID::Charge.new(
                  type: "overage",
                  name: rate_plan["name"],
                  price: rate_plan["pricing"][0]["overagePrice"],
                  billing_duration: :month,
                  zuora_product_rate_plan_charge_id: rate_plan["id"],
                )
              end
            )

            next
          end

          product_rate = GitHub.zuorest_client.create_product_rate_plan(
            Name: rate_plan_charge.name,
            EffectiveStartDate: GitHub::Billing.today.to_s,
            EffectiveEndDate: EFFECTIVE_END_DATE,
            ProductId: product_id,
          )

          objects = rate_plan_charge.product_rate_plan_charges.map do |rate_plan|
            {
              BillingPeriod: "Month",
              ChargeType: "Usage",
              DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
              Name: rate_plan[:name],
              ProductRatePlanId: product_rate["id"],
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

          created_product_rate_charges = GitHub.zuorest_client.create_action(
            type: "ProductRatePlanCharge",
            objects: objects,
          )

          product_rate_charges = created_product_rate_charges.map do |product_rate_charge|
            GitHub.zuorest_client.get_product_rate_plan_charge(product_rate_charge["Id"])
          end

          Billing::ProductUUID.create!(
            product_type: self.class.product_type,
            product_key: rate_plan_charge.name,
            name: rate_plan_charge.name,
            billing_cycle: :month,
            metered: true,
            zuora_product_id: product_id,
            zuora_product_rate_plan_id: product_rate["id"],
            zuora_product_rate_plan_charge_ids: zuora_product_rate_plan_charge_ids(product_rate_charges: product_rate_charges),
            charges: product_rate_charges.map do |rate_plan_charge|
              price = objects.detect { |o| o[:Name] == rate_plan_charge["Name"] }&.dig(:ProductRatePlanChargeTierData, :ProductRatePlanChargeTier, 0, :Price)

              Billing::ProductUUID::Charge.new(
                type: "overage",
                name: rate_plan_charge["Name"],
                price: price,
                billing_duration: :month,
                zuora_product_rate_plan_charge_id: rate_plan_charge["Id"],
              )
            end
          )
        end
      end
    end
  end
end
