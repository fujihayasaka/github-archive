# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  # This job knows how to leverage the Billing::SubscriptionItem::IapSynchronizer class for syncing up IAP
  # purchased subscriptions. It is important to note that it does not sync in-app purchased Pro subscriptions,
  # those are handled by the SynchronizeAppleIapSubscriptionJob class.
  #
  # We may want to consider consolidating both of these jobs/processes to help keep the network chatter down
  # between us and Apple's StoreKit API but for now we can keep them separate while we initially focus on
  # expanding IAP support for other products.
  class SynchronizeAppleIapSubscriptionItemsJob < BillingJob
    extend T::Helpers

    class SynchronizeError < StandardError; end

    schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

    # Used for datadog metrics
    KEY_PREFIX = "billing.synchronize_apple_iap_subscription_items_job"

    sig { returns(T.nilable(Integer)) }
    attr_accessor :subscription_item_id

    retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10 do |job, error|
      Failbot.report(error, subscription_item_id: job.subscription_item_id)
    end

    BATCH_SIZE = 25

    sig { void }
    def perform
      subscription_item_ids = T.let([], T::Array[Integer])

      subscription_item_ids = Billing::AppleSubscription.pluck(:subscription_item_id)

      GitHub.dogstats.count("#{KEY_PREFIX}.ids", subscription_item_ids.size)

      subscription_item_ids.each_slice(BATCH_SIZE) do |ids|
        subscription_items = Billing::SubscriptionItem.where(id: ids)

        subscription_items.each do |subscription_item|
          # This intended to be used when a GitHub::Restraint::UnableToLock error is raised
          @subscription_item_id = T.let(subscription_item.id, T.nilable(Integer))

          Billing::SubscriptionItem.throttle_writes_with_retry(max_retry_count: 5) do
            result = Billing::SubscriptionItem::IapSynchronizer.call(subscription_item)

            # Increment the stat for the result of the synchronization with proper tags with result status
            # and cancellation reason.
            GitHub.dogstats.increment(KEY_PREFIX, tags: derive_datadog_tags(result))

            # Success here (result.success?) means that the subscription item is in the correct state: either Apple
            # said its active so leave it alone or Apple said its not active and we were able to successfully
            # cancel it.
            #
            # Not a success here (!result.success?) means: Apple said to cancel the subscription but billing
            # could not, so that is a bad thing and we should report it.
            Failbot.report(
              SynchronizeError.new("Failed to synchronize subscription with apple"),
              subscription_item_id: subscription_item.id,
              cancellation_reason: result.cancellation_reason,
              errors: result.errors,
            ) unless result.success?
          end
        end
      end
    end

    private

    # Internal: Used for Datadog classification. Take a result object and return what Datadog
    #           tags we should use for incrementing metrics.
    sig { params(result: SubscriptionItem::IapSynchronizer::Result).returns(T::Array[String]) }
    def derive_datadog_tags(result)
      # If cancellation_reason isn't null it means Apple said to cancel it, so take that reason and
      # turn it into a DD tag like "not_found", "sandbox", or "expired". For null cancellation reasons we can
      # default to: "none" since Apple said to leave it alone.
      cancellation_reason_suffix = result.cancellation_reason ? T.must(result.cancellation_reason).serialize : "none"

      [
        "synchronized:#{result.success?}",
        "cancellation_reason:#{cancellation_reason_suffix}"
      ]
    end
  end
end
