# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    class InAppPurchasing
      # Composite object that wraps up a Billing::SubscriptionItem and knows how to act on it in the context of
      # in-app purchasing. This cannot and should not be used for non-in-app purchased and non-copilot subscription
      # items. Attempting to do so will raise an ArgumentError during initialization.
      class CopilotSubscriptionItem
        # Note: We are hard-coding and duplicating these here since we cannot directly access the Copilot package
        # from the Billing package. The Copilot constant definitions live here:
        # packages/copilot/app/public/copilot.rb. This is just a reminder that, if these values change, to remember
        # to change the corresponding values.
        PRODUCT_TYPE = "github.copilot"
        PRO_PRODUCT_KEY = "v0"
        PRO_PLUS_PRODUCT_KEY = "pro-plus"

        private_constant :PRODUCT_TYPE,
          :PRO_PRODUCT_KEY,
          :PRO_PLUS_PRODUCT_KEY

        sig { returns(Billing::SubscriptionItem) }
        attr_reader :subscription_item

        delegate :user, :in_app_purchase, to: :subscription_item

        sig { params(subscription_item: Billing::SubscriptionItem).void }
        def initialize(subscription_item)
          if !subscription_item.in_app_purchase?
            raise ArgumentError, "This is only applicable for in-app purchased subscription items."
          end

          if T.must(subscription_item.product_uuid).product_type != PRODUCT_TYPE
            raise ArgumentError, "This is only applicable for Copilot subscription items."
          end

          @subscription_item = subscription_item
        end

        sig { returns(T::Boolean) }
        def pro_plus?
          T.must(subscription_item.product_uuid).product_key == PRO_PLUS_PRODUCT_KEY
        end

        sig { returns(SubscriptionItems::ResultStruct) }
        def cancel
          # This is a special case: technically we should not be calling cancel on a subscription item that is already
          # cancelled. However, we need to do this to ensure that the in-app purchase record has been removed
          # even if the subscription item is already cancelled.
          if subscription_item.cancelled?
            # Let's track how many times this case pops up.
            GitHub.dogstats.increment("billing.iap.copilot_subscription_item.cancel_called_for_cancelled_item")

            # Should have already been called but if we reached this state then it was due to one of the IAP
            # records existing AND Apple/Google are telling us that it should be cancelled.
            subscription_item.destroy_in_app_purchase_subscriptions!

            return SubscriptionItems::ResultStruct.new(
              subscription_item:,
              result: ResultStruct.new(success: true)
            )
          end

          # Make the call to cancel the subscription.
          # We are going to force it here to keep it synchronous within this classes execution flow.
          subscription_item.cancel!(force: true, allow_cancelling_iap: true)
        end

        sig { returns(SubscriptionItems::ResultStruct) }
        def downgrade_pro_plus
          raise ArgumentError, "This subscription item is not a Copilot Pro Plus subscription." unless pro_plus?

          Billing::UpdateSubscriptionItem.new(
            quantity: 1,
            viewer: user,
            subscribable: pro_subscribable,
            plan_subscription: user.plan_subscription,
            in_app_purchase: in_app_purchase,
            force: true
          ).call
        end

        private

        sig { returns(Product::ProductIdentifier) }
        def pro_product_identifier
          Product::ProductIdentifier.new(
            product_type: PRODUCT_TYPE,
            product_key: PRO_PRODUCT_KEY,
            billing_cycle: Public::SubscriptionItems::BillingCycle::Month
          )
        end

        sig { returns(ProductUUID) }
        def pro_subscribable
          product_uuid_conditions = pro_product_identifier.serialize.merge(metered: false)

          # We are relying that there will always be a product UUID for Copilot Pro.
          # If we cannot find it then fail fast: we ran into an exceptional case.
          T.must(ProductUUID.where(product_uuid_conditions).first)
        end
      end
    end
  end
end
