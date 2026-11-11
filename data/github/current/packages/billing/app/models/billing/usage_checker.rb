# typed: true
# frozen_string_literal: true

require "scientist"

module Billing
  class UsageChecker
    include GitHub::Memoizer
    ALL_PRODUCTS = %w[actions packages shared_storage codespaces git_lfs ghec ghas copilot].freeze

    class UsageResult < T::Struct
      const :net_amount_in_cents, Integer
      const :gross_amount_in_cents, Integer
    end

    attr_reader :account, :product_names

    # args
    #   :account - The account requesting the check. Can be user, org or enterprise org or enterprise
    #   :product_names - Array of product names
    #   :timeout - Time in Seconds - unused currently
    def initialize(account:, product_names: ALL_PRODUCTS, timeout: nil)
      @account = account
      @product_names = product_names
    end

    # Public: Returns a UsageResult struct containing both net and gross usage in cents.
    sig { returns(UsageResult) }
    def usage_result
      return UsageResult.new(net_amount_in_cents: 0, gross_amount_in_cents: 0) unless account.customer&.present?

      billing_platform_usage_result
    end

    # Public: Returns the total metered net usage in cents for the account
    sig { returns(Integer) }
    def total_usage_in_cents
      usage_result.net_amount_in_cents
    end

    # Public: Returns the total metered gross usage in cents for the account.
    # Accepts an optional product_names to restrict which products contribute to the gross total.
    # Defaults to the instance's product_names when not specified.
    sig { params(product_names: T::Array[String]).returns(Integer) }
    def total_gross_usage_in_cents(product_names: self.product_names)
      return 0 unless account.customer&.present?
      if product_names == ALL_PRODUCTS
        return usage_result.gross_amount_in_cents
      end

      items = billing_platform_usage_results[:netUsageItems].select { |item| product_names.include?(item[:product]) }
      Billing::Money.parse(items.sum { |u| u[:grossAmount] }).cents
    end

    private

    # Private: Returns a UsageResult computed from the billing platform response
    sig { returns(UsageResult) }
    memoize def billing_platform_usage_result
      items = billing_platform_usage_results[:netUsageItems].select { |item| product_names.include? item[:product] }
      net_total = items.sum { |u| u[:netAmount] }
      gross_total = items.sum { |u| u[:grossAmount] }

      UsageResult.new(
        net_amount_in_cents: Billing::Money.parse(net_total).cents,
        gross_amount_in_cents: Billing::Money.parse(gross_total).cents,
      )
    end

    # Private: Returns an array of usages across products from billing platform
    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def billing_platform_usage_results
      billing_platform_client = Billing::Platform::Api::Client.new
      billing_cycle_start_date = account.current_metered_billing_cycle_starts_at

      response = billing_platform_client.get_net_usage_line_items(
        usage_entity_id: account.customer.id.to_s,
        billing_period: BillingPlatform::Base::BillingPeriod::Monthly,
        year: billing_cycle_start_date.year,
        month: billing_cycle_start_date.month,
        day: nil,
        hour: nil,
      )

      raise response if response.is_a?(Billing::Platform::Api::Error)
      response
    end
  end
end
