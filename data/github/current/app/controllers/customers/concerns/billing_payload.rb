# typed: true
# frozen_string_literal: true

module Customers::Concerns::BillingPayload
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    sig { params(subscription_item: T.nilable(Billing::Public::SubscriptionItem)).returns(T.nilable({ price: Float, name: String, billingCycle: String, hasPendingDowngrade: T::Boolean })) }
    def subscription_item_payload(subscription_item)
      return nil unless subscription_item.present?
      # If the pending change is for a product that is different from the current one, it is considered a downgrade
      # Pending cycle changes aren't considered a downgrade in this scenario
      has_pending_downgrade = subscription_item.pending_cancellation? ||
        (
          subscription_item.pending_change? &&
          T.must(subscription_item.pending_change_identifier).product_key != subscription_item.product_identifier.product_key
        )
      {
        price: subscription_item.price.to_f,
        name: subscription_item.name,
        billingCycle: subscription_item.interval.to_s,
        hasPendingDowngrade: !!has_pending_downgrade
      }
    end
  end
end
