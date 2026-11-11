# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Customers
      class PlanSubscriptionsComponent < ApplicationComponent
        sig { params(customer: Customer, plan_subscriptions: T.untyped).void }
        def initialize(customer:, plan_subscriptions:)
          @customer = customer
          @plan_subscriptions = plan_subscriptions
        end

        private

        sig { returns(Customer) }
        attr_reader :customer

        sig { returns(T.untyped) }
        attr_reader :plan_subscriptions

        sig { returns(T::Boolean) }
        def has_subscriptions?
          plan_subscriptions.any?
        end

        sig { params(subscription: T.untyped).returns(String) }
        def subscription_type_label(subscription)
          if subscription.respond_to?(:sales_serve?) && subscription.sales_serve?
            "Sales Serve"
          elsif subscription.purpose.to_s == "sponsors"
            "Sponsors"
          else
            "General"
          end
        end

        sig { params(subscription: T.untyped).returns(Symbol) }
        def subscription_type_scheme(subscription)
          if subscription.respond_to?(:sales_serve?) && subscription.sales_serve?
            :done
          elsif subscription.purpose.to_s == "sponsors"
            :sponsors
          else
            :accent
          end
        end
      end
    end
  end
end
