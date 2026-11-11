# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      class View
        sig { params(hash: T::Hash[Symbol, T.untyped]).returns(View) }
        def self.from_hash(hash)
          new(
            paywall_products: (hash[:paywall_products] || []).map { |item_hash| Product.from_hash(item_hash) },
            disclaimers: (hash[:disclaimers] || []).map(&:to_s),
            all_features: (hash[:all_features] || []).map { |item_hash| FeatureComparisonSection.from_hash(item_hash) }
          )
        end

        sig { returns(T::Array[Product]) }
        attr_reader :paywall_products

        sig { returns(T::Array[String]) }
        attr_reader :disclaimers

        sig { returns(T::Array[FeatureComparisonSection]) }
        attr_reader :all_features

        sig do
          params(
            paywall_products: T::Array[Product],
            disclaimers: T::Array[String],
            all_features: T::Array[FeatureComparisonSection]
          ).void
        end
        def initialize(paywall_products:, disclaimers:, all_features:)
          @paywall_products = paywall_products
          @disclaimers = disclaimers
          @all_features = all_features
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            paywall_products: paywall_products.map(&:to_hash),
            disclaimers:,
            all_features: all_features.map(&:to_hash)
          }
        end

        sig { params(other: View).returns(T::Boolean) }
        def eql?(other)
          self.class == other.class &&
            paywall_products == other.paywall_products &&
            disclaimers == other.disclaimers &&
            all_features == other.all_features
        end
        alias :== eql?
      end
    end
  end
end
