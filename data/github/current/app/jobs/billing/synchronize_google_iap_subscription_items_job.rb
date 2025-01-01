# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  # This job knows how to leverage the Billing::SubscriptionItem::GoogleIapSynchronizer class for syncing up Google IAP
  # purchased subscriptions.
  class SynchronizeGoogleIapSubscriptionItemsJob < BillingJob
    extend T::Helpers

    class SynchronizeError < StandardError; end

    schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

    # Used for datadog metrics
    KEY_PREFIX = "billing.synchronize_google_iap_subscription_items_job"

    sig { returns(T.nilable(Integer)) }
    attr_accessor :subscription_item_id

    retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10 do |job, error|
      Failbot.report(error, subscription_item_id: job.subscription_item_id)
    end

    BATCH_SIZE = 25

    sig { void }
    def perform
      subscription_item_ids = Billing::GoogleSubscription.pluck(:subscription_item_id)

      GitHub.dogstats.count("#{KEY_PREFIX}.ids", subscription_item_ids.size)

      subscription_item_ids.each_slice(BATCH_SIZE) do |ids|
        subscription_items = Billing::SubscriptionItem.where(id: ids)

        subscription_items.each do |subscription_item|
          # This intended to be used when a GitHub::Restraint::UnableToLock error is raised
          @subscription_item_id = T.let(subscription_item.id, T.nilable(Integer))

          Billing::SubscriptionItem.throttle_writes_with_retry(max_retry_count: 5) do
            result = Billing::SubscriptionItem::GoogleIapSynchronizer.call(subscription_item)

            # Increment the stat for the result of the synchronization with proper tags with result status
            # and cancellation reason.
            GitHub.dogstats.increment(KEY_PREFIX, tags: derive_datadog_tags(result))

            # Success here (result.success?) means that the subscription item is in the correct state: either Google
            # said its active so leave it alone or Google said its not active and we were able to successfully
            # cancel it.
            #
            # Not a success here (!result.success?) means: Google said to cancel the subscription but billing
            # could not, so that is a bad thing and we should report it.
            Failbot.report(
              SynchronizeError.new("Failed to synchronize subscription with Google"),
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
    sig { params(result: SubscriptionItem::GoogleIapSynchronizer::Result).returns(T::Array[String]) }
    def derive_datadog_tags(result)
      # If cancellation_reason isn't null it means Google said to cancel it, so take that reason and
      # turn it into a DD tag like "not_found", "test", or "expired". For null cancellation reasons we can
      # default to: "none" since Google said to leave it alone.
      cancellation_reason_suffix = result.cancellation_reason ? T.must(result.cancellation_reason).serialize : "none"

      [
        "synchronized:#{result.success?}",
        "cancellation_reason:#{cancellation_reason_suffix}"
      ]
    end
  end
end
