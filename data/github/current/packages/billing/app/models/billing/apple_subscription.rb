# typed: strict
# frozen_string_literal: true

module Billing
  # Holds information about a user's Apple subscription for the associated SubscriptionItem record.
  #
  # 🚨🚨 WARNING 🚨🚨
  # Apple is the ultimate source-of-truth for this information. We should never, ever delete these records
  # unless Apple says the subscription is in-active (cancelled, expired, etc.) If we delete these records
  # without Apple telling us that the subscription is inactive on their side then we run the risk of double-billing
  # users. The root cause of this is that Apple does not provide a server-to-server API where we can cancel
  # user subscriptions on behalf of the user. The only way subscriptions get cancelled, on the Apple side, is
  # if the user personally cancels the subscription.
  class AppleSubscription < ApplicationRecord::Domain::Billing

    DATA_DOG_KEY = "billing.apple_subscription"

    # A SubscriptionItem record is required for every AppleSubscription record.
    belongs_to :subscription_item,
      inverse_of: :apple_subscription,
      optional: false

    # We should only ever have one AppleSubscription record per SubscriptionItem record.
    validates :subscription_item_id, uniqueness: true

    # We need the original_transaction_id to be able to call Apple's StoreKit API to retrieve
    # the latest subscription information.
    validates :original_transaction_id,
      presence: true,
      length: { maximum: 64 },
      uniqueness: { allow_blank: true }

    before_destroy :log_destruction

    private

    # This callback will log the important parts of this record before it is destroyed.
    # We really need to know when we decide to delete these records since Apple is the source of truth.
    # Not having this data be retrievable could lead to us not being able to fix subscriptions in the backend
    # on behalf of the user.
    sig { void }
    def log_destruction
      GitHub.dogstats.increment("#{DATA_DOG_KEY}", tags: ["action:destroy"])

      GitHub.logger.info("A Billing::AppleSubscription record is being destroyed.",
        "code.namespace" => "Billing::AppleSubscription",
        "code.function" => "destroy",
        "gh.apple_subscription.id" => id,
        "gh.apple_subscription.subscription_item_id" => subscription_item_id,
        "gh.apple_subscription.original_transaction_id" => original_transaction_id,
        "gh.plan_subscription.user_id" => subscription_item&.plan_subscription&.user_id,
      )
    end
  end
end
