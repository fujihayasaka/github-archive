# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  class CancelSubscriptionItemsJob < BillingJob

    retry_on StandardError
    retry_on_dirty_exit

    queue_as :cancel_subscription_items

    sig do
      params(
        user_id: Integer,
        force: T::Boolean,
        skip_sync: T::Boolean,
        subscribable_type: T.nilable(String),
        sdn_suspension: T::Boolean,
        send_email: T::Boolean,
        event: T.nilable(Symbol),
        tos_reason: T.nilable(String),
        dsa_source: T.nilable(String)
      ).void
    end
    def perform(user_id:, force: false, skip_sync: false, subscribable_type: nil, sdn_suspension: false, send_email: false, event: nil, tos_reason: nil, dsa_source: nil)
      return unless user = User.find_by(id: user_id)

      results = with_write do
        user.cancel_subscription_items!(force: force, skip_sync: skip_sync, subscribable_type: subscribable_type)
      end
      cancelled_subscription_item_names = results.filter_map do |result|
        result.subscription_item.listing_name || result.subscription_item.subscribable_name if result.result.success
      end
      user.send_suspension_email(cancelled_subscription_item_names, tos_reason: tos_reason, dsa_source: dsa_source) if (dsa_source || send_email) && event == :suspension
      user.send_billing_lock_email(cancelled_subscription_item_names) if send_email && event == :billing_lock
      GitHub.dogstats.increment("billing.cancel_subscription_items_job", tags: ["send_email:#{send_email}", "sdn_suspension:#{sdn_suspension}", "event:#{event}"])
    end
  end
end
