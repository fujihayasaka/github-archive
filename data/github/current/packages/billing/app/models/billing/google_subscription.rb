# typed: strict
# frozen_string_literal: true

module Billing
  # Holds information about a user's Google subscription for the associated SubscriptionItem record.
  #
  # 🚨🚨 WARNING 🚨🚨
  # Google is the ultimate source-of-truth for this information. We should never, ever delete these records
  # unless Google says the subscription is in-active (cancelled, expired, etc.) If we delete these records
  # without Google telling is that the subscription is inactive on their side then we run the risk of double-billing
  # users. The root cause of this is that Google does not provide a server-to-server API where we can cancel
  # user subscriptions on behalf of the user. The only way subscriptions get cancelled, on the Google side, is
  # if the user personally cancels the subscription.
  class GoogleSubscription < ApplicationRecord::Domain::Billing
    extend T::Sig

    DATA_DOG_KEY = "billing.google_subscription"

    # A SubscriptionItem record is required for every GoogleSubscription record.
    belongs_to :subscription_item,
      inverse_of: :google_subscription,
      optional: false

    # We should only ever have one GoogleSubscription record per SubscriptionItem record.
    validates :subscription_item_id, uniqueness: true

    # We need the purchase_token to be able to call Google's Android Publisher API to retrieve
    # the latest subscription information.
    validates :purchase_token,
      presence: true,
      length: { maximum: 255 },
      uniqueness: { allow_blank: true, case_sensitive: false }

    before_destroy :log_destruction

    private

    # This callback will log the important parts of this record before it is destroyed.
    # We really need to know when we decide to delete these records since Google is the source of truth.
    # Not having this data be retrievable could lead to us not being able to fix subscriptions in the backend
    # on behalf of the user.
    sig { void }
    def log_destruction
      GitHub.dogstats.increment("#{DATA_DOG_KEY}", tags: ["action:destroy"])

      GitHub.logger.info("A Billing::GoogleSubscription record is being destroyed.",
        "code.namespace" => "Billing::GoogleSubscription",
        "code.function" => "destroy",
        "gh.google_subscription.id" => id,
        "gh.google_subscription.subscription_item_id" => subscription_item_id,
        "gh.google_subscription.purchase_token" => purchase_token,
        "gh.plan_subscription.user_id" => subscription_item&.plan_subscription&.user_id,
      )
    end
  end
end
