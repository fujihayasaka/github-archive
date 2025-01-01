# typed: true
# frozen_string_literal: true

module Billing
  # This class understands how to leverage the Billing::PlanSubscription::AppleIapSynchronizer for
  # syncing up Pro subscriptions purchased via Apple's App Store. It is important to note that it does not
  # sync SubscriptionItem-based subscriptions (i.e Copilot for Individual licenses), those are handled by
  # the SynchronizeAppleIapSubscriptionItemsJob.
  class SynchronizeAppleIapSubscriptionJob < ApplicationJob
    class SynchronizeError < StandardError; end

    schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

    queue_as :billing

    attr_accessor :plan_subscription_id

    retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10 do |job, error|
      Failbot.report(error, plan_subscription_id: job.plan_subscription_id)
    end

    BATCH_SIZE = 25

    def perform
      subscription_ids = T.let([], T::Array[Integer])

      subscription_ids = Billing::PlanSubscription.where.not(apple_transaction_id: nil).pluck(:id)

      GitHub.dogstats.count("billing.plan_subscription.apple_iap_job.ids", subscription_ids.size)

      subscription_ids.each_slice(BATCH_SIZE) do |ids|
        subscriptions = Billing::PlanSubscription.where(id: ids)

        subscriptions.each do |subscription|
          # This intended to be used when a GitHub::Restraint::UnableToLock error is raised
          @plan_subscription_id = subscription.id

          Billing::PlanSubscription.throttle_writes_with_retry(max_retry_count: 5) do
            lock(subscription) do
              result = with_write { Billing::PlanSubscription::AppleIapSynchronizer.call(subscription) }

              if result.success?
                GitHub.dogstats.increment("billing.plan_subscription.apple_iap_job.synchronized")
              else
                GitHub.dogstats.increment("billing.plan_subscription.apple_iap_job.not_synchronized")
                Failbot.report(
                  SynchronizeError.new("Failed to synchronize subscription with apple"),
                  plan_subscription: subscription.id,
                  errors: result.error_message,
                )
              end
            end
          end
        end
      end
    end

    private

    # Internal: Use a GitHub::Restraint to prevent simultaneous updates
    def lock(subscription, &block)
      lock_key = "billing.plan_subscription.apple.#{subscription.id}"

      restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 5.minutes, &block)
    end

    # Internal: The restraint for locking and preventing simultaneous updates
    #
    # Returns GitHub::Restraint
    def restraint
      @restraint ||= GitHub::Restraint.new
    end
  end
end
