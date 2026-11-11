# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220818061815_create_copilot_for_business_product_in_zuora.rb --verbose | tee -a /tmp/create_copilot_for_business_product_in_zuora.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220818061815_create_copilot_for_business_product_in_zuora.rb --verbose -w | tee -a /tmp/create_copilot_for_business_product_in_zuora.log
#
module GitHub
  module Transitions
    class CreateCopilotForBusinessProductInZuora < Transition
      include ::Billing::ZuoraProduct::ZuoraSettings

      # Uncomment this if running this transition with Divvy
      # include Divvy::Parallelizable

      # #dotcom-db-migration-help is your friend, and can help code review
      # transitions before they're run to make sure they're being nice to our
      # database clusters. We're usually looking for a few things in transitions:
      #   1. Iterators: We want to query the database for records to change in batches
      #   2. Read-Only Replicas: If we're reading data to be changed, we want to do it on
      #      the read-only replicas to keep load off the primary.
      #   3. Throttle writes: We want to make sure we wrap any actual writes to the primary
      #      in a `throttle_with_retry` block, which should be called on the most specific
      #      `ApplicationRecord::*` class/subclass or object. This will make sure we don't
      #      overwhelm primary and cause replication lag.
      #   4. Efficient queries: We want to avoid massive table scans, so make sure your
      #      query has an index or is performant and safe without one.
      #
      #   For more information on all this, checkout the transition docs at
      #   https://thehub.github.com/engineering/development-and-ops/dotcom/migrations-and-transitions/transitions/

      PRODUCT_TYPE = "github.copilot"
      PRODUCT_KEY = "business.v0"

      # Returns nothing.
      def perform
        return unless GitHub.billing_enabled?
        log "Syncing - GitHub Copilot for Business"
        GitHub.zuorest_client.timeout = 60

        if existing_copilot_for_business_product_uuid?
          log "Skipping - GitHub Copilot for Business already exists"
        else
          create_copilot_for_business_product unless dry_run?
        end
      end

      private

      def create_copilot_for_business_product
        name = "GitHub Copilot for Business"
        unit_cost = ::Billing::Money.new(19 * 100)
        billing_period = User::BillingDependency::MONTHLY_PLAN

        zuora_product_id = create_if_not_exists_zuora_product(name: name)
        zuora_product_rate_plan = create_if_not_exists_zuora_product_rate_plan(product_id: zuora_product_id, name: name)

        charge_name = "GitHub Copilot"
        zuora_product_rate_plan_charge = create_if_not_exists_zuora_product_rate_plan_charge(
          name: charge_name,
          billing_period: billing_period,
          unit_cost: unit_cost,
          product_rate_plan: zuora_product_rate_plan,
          product_id: zuora_product_id
        )

        ::Billing::ProductUUID.create!(
          product_type: PRODUCT_TYPE,
          product_key: PRODUCT_KEY,
          name: name,
          billing_cycle: billing_period,
          metered: true,
          zuora_product_id: zuora_product_id,
          zuora_product_rate_plan_id: zuora_product_rate_plan["id"],
          zuora_product_rate_plan_charge_ids: {
            user_month: zuora_product_rate_plan_charge["id"]
          },
          charges: [
            ::Billing::ProductUUID::Charge.new(
              type: "per_unit",
              name: zuora_product_rate_plan_charge["name"],
              price: zuora_product_rate_plan_charge["pricing"][0]["price"],
              billing_duration: billing_period,
              zuora_product_rate_plan_charge_id: zuora_product_rate_plan_charge["id"],
            )
          ]
        )
      end

      def create_if_not_exists_zuora_product_rate_plan_charge(name:, billing_period:, unit_cost:, product_rate_plan:, product_id:)
        raise "Product rate plan not compatible" unless product_rate_plan["id"].present?

        existing_charge = product_rate_plan["productRatePlanCharges"].find { |charge| charge["name"] == name }
        return existing_charge if existing_charge

        response = GitHub.zuorest_client.create_action(
          type: "ProductRatePlanCharge",
          objects: [{
            BillingPeriod: billing_period.capitalize,
            ChargeType: "Usage",
            DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
            Name: name,
            ProductRatePlanId: product_rate_plan["id"],
            RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
            TaxCode: TAX_CODE,
            TaxMode: "TaxExclusive",
            Taxable: false,
            TriggerEvent: "ContractEffective",
            ChargeModel: "Per Unit Pricing",
            UOM: "User Month",
            ListPrice: unit_cost.dollars,
            ProductRatePlanChargeTierData: {
              ProductRatePlanChargeTier: [
                {
                  Currency: "USD",
                  Price: unit_cost.dollars,
                  PriceFormat: "Per Unit",
                },
              ],
            },
          }]
        ).first
        unless response["Success"]
          raise "Could not create ProductRatePlanCharge for #{name} #{response["Errors"]}"
        end

        reloaded_product_rate_plan = find_zuora_product_rate_plan(product_id: product_id, name: product_rate_plan["name"])
        unless reloaded_product_rate_plan
          raise "Unable to reload product rate plan for #{product_rate_plan["name"]} product ID #{product_id}"
        end

        reloaded_product_rate_plan["productRatePlanCharges"].find { |charge| charge["name"] == name }
      end

      def create_if_not_exists_zuora_product_rate_plan(product_id:, name:)
        existing_product_rate_plan = find_zuora_product_rate_plan(product_id: product_id, name: name)
        unless existing_product_rate_plan
          GitHub.zuorest_client.create_product_rate_plan(
            Name: name,
            EffectiveStartDate: GitHub::Billing.today.to_s,
            EffectiveEndDate: EFFECTIVE_END_DATE,
            ProductId: product_id,
          )

          existing_product_rate_plan = find_zuora_product_rate_plan(product_id: product_id, name: name)
          unless existing_product_rate_plan
            raise "Could not find product rate plan for Zuora Product:#{product_id} - #{name}"
          end
        end

        existing_product_rate_plan
      end

      def create_if_not_exists_zuora_product(name:)
        ::Billing::ProductUUID.find_by(product_type: PRODUCT_TYPE, product_key: PRODUCT_KEY)&.zuora_product_id ||
          GitHub.zuorest_client.get_product_id_for_name(name) ||
          GitHub.zuorest_client.create_product(
            Name: name,
            EffectiveStartDate: GitHub::Billing.today.to_s,
            EffectiveEndDate: EFFECTIVE_END_DATE,
          )["Id"]
      end

      def find_zuora_product_rate_plan(product_id:, name:)
        remote_product_rate_plans = GitHub.zuorest_client.get_product_rate_plan(product_id)
        remote_product_rate_plans["productRatePlans"].find { |rp| rp["name"] == name }
      end

      def existing_copilot_for_business_product_uuid?
        ::Billing::ProductUUID.where(
          product_type: PRODUCT_TYPE, product_key: PRODUCT_KEY
        ).exists?
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::CreateCopilotForBusinessProductInZuora.new(**options)
  transition.run
end
