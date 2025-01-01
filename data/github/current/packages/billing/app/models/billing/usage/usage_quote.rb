# typed: strict
# frozen_string_literal: true

module Billing::Usage
  class UsageQuote
    # Schema
    #  {
    #   product_name: String,
    #   product_sku_name: String,
    #   total_historical_usage: {
    #     estimated_cost: {
    #       currency: String,
    #       subunits: Float
    #     },
    #     quantity: Float,
    #     effective_quantity: Float,
    #     billable_quantity: Float
    #   },
    #   marginal_proposed_usage: {
    #     estimated_cost: {
    #       currency: String,
    #       subunits: Float
    #     },
    #     quantity: Float,
    #     effective_quantity: Float,
    #     billable_quantity: Float
    #   },
    #   total_proposed_usage: {
    #     estimated_cost: {
    #       currency: String,
    #       subunits: Float
    #     },
    #     quantity: Float,
    #     effective_quantity: Float,
    #     billable_quantity: Float
    #   }
    # }

    sig { params(raw_usage_quote: T::Hash[T.untyped, T.untyped]).void }
    def initialize(raw_usage_quote)
      @raw_usage_quote = T.let(raw_usage_quote.with_indifferent_access, T::Hash[Symbol, T.untyped])
    end

    delegate :[], to: :raw_usage_quote

    sig { returns(String) }
    def product_name
      raw_usage_quote[:product_name]
    end

    sig { returns(String) }
    def product_sku_name
      raw_usage_quote[:product_sku_name]
    end

    sig { returns(Float) }
    def proposed_estimated_cost
      raw_usage_quote[:total_proposed_usage][:estimated_cost][:subunits].to_f
    end

    sig { returns(Float) }
    def proposed_quantity
      raw_usage_quote[:total_proposed_usage][:quantity].to_f
    end

    sig { returns(Float) }
    def proposed_effective_quantity
      raw_usage_quote[:total_proposed_usage][:effective_quantity].to_f
    end

    sig { returns(Float) }
    def proposed_billable_quantity
      raw_usage_quote[:total_proposed_usage][:billable_quantity].to_f
    end

    sig { returns(T::Boolean) }
    def actions_linux?
      product_name == "actions" && product_sku_name == "linux"
    end

    sig { returns(T::Boolean) }
    def packages?
      product_name == "packages" && product_sku_name == "default"
    end

    sig { returns(T::Boolean) }
    def shared_storage?
      product_name == "shared_storage" && product_sku_name == "default"
    end

    private

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :raw_usage_quote
  end
end
