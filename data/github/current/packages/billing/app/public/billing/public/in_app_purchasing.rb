# typed: strict
# frozen_string_literal: true

module Billing
  module Public
    # Composite object that wraps up a user and provides a unified way to check against both Apple and Google
    # IAP storage records. Callers looking to tap into IAP data should try to program against this interface
    # if possible.
    #
    # It should become more apparent why this interface is necessary as our IAP logic to support both Google and
    # Apple increases in scope and complexity.
    class InAppPurchasing
      extend T::Sig

      include GitHub::Memoizer

      sig { returns(User) }
      attr_reader :user

      sig { params(user: User).void }
      def initialize(user)
        @user = user
      end

      # Public: Returns true if the user has any active in-app purchase subscriptions, false if none exist.
      sig { returns(T::Boolean) }
      def in_app_purchases?
        apple_in_app_purchases? || google_in_app_purchases?
      end

      sig { returns(T::Boolean) }
      def apple_in_app_purchases?
        # Check for pro subscription via IAP
        return true if user.apple_iap_subscription?
        return true if subscription_ids && AppleSubscription.exists?(subscription_item_id: subscription_ids)
        false
      end
      memoize :apple_in_app_purchases?

      sig { returns(T::Boolean) }
      def google_in_app_purchases?
        return true if subscription_ids && GoogleSubscription.exists?(subscription_item_id: subscription_ids)
        false
      end
      memoize :google_in_app_purchases?

      private

      sig { returns(T.nilable(T::Array[Numeric])) }
      def subscription_ids
        if (plan_subscription = user.plan_subscription)
          plan_subscription.subscription_items.active.pluck(:id)
        end
      end
      memoize :subscription_ids
    end
  end
end
