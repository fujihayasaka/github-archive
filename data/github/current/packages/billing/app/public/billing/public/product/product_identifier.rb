# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    module Product
      class ProductIdentifier < T::Struct
        extend T::Sig

        const :product_type, String
        const :product_key, String
        const :billing_cycle, T.nilable(Billing::Public::SubscriptionItems::BillingCycle)

        # T::Structs use referencial equality by default: https://sorbet.org/docs/tstruct#structural-vs-reference-equality
        sig { params(other: ProductIdentifier).returns(T::Boolean) }
        def ==(other)
          product_type == other.product_type &&
          product_key == other.product_key &&
          billing_cycle == other.billing_cycle
        end


        sig { params(other: ProductIdentifier, match_billing_cycle: T::Boolean).returns(T::Boolean) }
        def same?(other, match_billing_cycle: true)
          return (self == other) if match_billing_cycle


          product_type == other.product_type &&
          product_key == other.product_key
        end
      end
    end
  end
end
