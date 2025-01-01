# typed: strict
# frozen_string_literal: true

module Billing::Usage
  class ProductUsage
    extend T::Sig
    include GitHub::Memoizer

    sig { returns(ActiveSupport::HashWithIndifferentAccess) }
    attr_reader :raw_product_usage

    sig { params(raw_product_usage: T::Hash[Symbol, T.untyped]).void }
    def initialize(raw_product_usage)
      @raw_product_usage = T.let(
        raw_product_usage.with_indifferent_access,
        ActiveSupport::HashWithIndifferentAccess
      )
    end

    sig { returns(String) }
    memoize def product_name
      raw_product_usage[:product][:name]
    end

    sig { returns(String) }
    memoize def product_sku_name
      raw_product_usage[:product_sku][:name]
    end

    sig { returns(String) }
    memoize def unit_of_measure
      raw_product_usage[:product_sku][:unit_of_measure][:name]
    end

    sig { returns(Numeric) }
    memoize def estimated_cost
      raw_product_usage[:usage][:estimated_cost][:subunits] || 0
    end

    sig { returns(Numeric) }
    memoize def quantity
      raw_product_usage[:usage][:quantity]
    end

    sig { returns(Numeric) }
    memoize def effective_quantity
      raw_product_usage[:usage][:effective_quantity] || 0
    end

    sig { returns(Numeric) }
    memoize def billable_quantity
      raw_product_usage[:usage][:billable_quantity] || 0
    end
  end
end
