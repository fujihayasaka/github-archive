# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    module Product
      class ProductIdentifier < T::Struct

        const :product_type, String
        const :product_key, T.nilable(String)
        const :billing_cycle, T.nilable(Billing::Public::SubscriptionItems::BillingCycle)

        # T::Structs use referencial equality by default: https://sorbet.org/docs/tstruct#structural-vs-reference-equality
        sig { params(other: ProductIdentifier).returns(T::Boolean) }
        def ==(other)
          product_type == other.product_type &&
          product_key == other.product_key &&
          billing_cycle == other.billing_cycle
        end


        sig { params(other: ProductIdentifier, match_billing_cycle: T::Boolean, match_product_key: T::Boolean).returns(T::Boolean) }
        def same?(other, match_billing_cycle: true, match_product_key: true)
          product_match_conditions = []
          product_match_conditions << (product_type == other.product_type)
          product_match_conditions << (product_key == other.product_key) if match_product_key
          product_match_conditions << (billing_cycle == other.billing_cycle) if match_billing_cycle

          product_match_conditions.all?
        end
      end
    end
  end
end
