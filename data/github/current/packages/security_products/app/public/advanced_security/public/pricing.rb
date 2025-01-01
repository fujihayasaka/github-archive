# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  module Public
    module Pricing
      include Kernel
      include Billing::ProrationMath
      class ForbiddenError < StandardError; end

      # This price currently does not handle proration
      sig do
        params(
          seats: Integer,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle,
        ).returns(Billing::Money)
      end
      def advanced_security_price(seats:, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        T.bind(self, T.any(User, Organization, Business))
        if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year && !self.feature_enabled?(:ghas_self_serve_post_mvp)
          raise ForbiddenError.new("Cannot display price for an advanced security subscription on an annual billing cycle")
        end
        product_identifier = if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Month
          AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
        else
          AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_YEARLY_PRODUCT
        end

        # TODO: Determine service percentage remaining from the user's subscription item
        service_percentage_remaining = 1
        if self.subscribed_to_product?(product_identifier)
          result = ::Billing::Public::SubscriptionItem.all_active(product: product_identifier, account: self)
          subscription_items = result.value { [] }
          product = subscription_items.sole
          base_price = product.price
        else
          product_uuid = Billing::ProductUUID.where(product_identifier.serialize).sole
          base_price = product_uuid.base_price(duration: product_identifier.billing_cycle&.serialize)
        end

        new_price = base_price * seats
        prorate(new_price, service_percentage_remaining)
      end
    end
  end
end
