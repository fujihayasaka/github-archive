# typed: strict
# frozen_string_literal: true

module Billing
  # Our billing system is not the source of truth for in-app purchased subscriptions. This means cancelling
  # in-app purchased subscriptions within our system comes at a cost of potentially causing double billing
  # for users. Nonetheless, there are specific circumstance we _do_ want to cancel in-app purchased subscriptions
  # within our GitHub system. There are two main examples of such a case:
  #   1. Sandbox subscriptions within external app stores are set to expire shortly after they are created.
  #      In this case, this job could be viewed as a cleanup job to purge sandbox subscriptions.
  #   2. Copilot for Individual licenses are able to be cancelled and transferred to Copilot for Business licenses.
  #      This is definitely an issue but it is one which has been worked through, with heavy coordination,
  #      with the billing, copilot product, and mobile teams to ensure the user will be presented with the
  #      appropriate call-to-actions to cancel their in-app subscriptions within their respective app store.
  #      This is the one known case where our billing system is _not_ the source of truth but we must all this
  #      case.
  # There may be more complex scenarios in the future, like the one described above for Copilot, and thats OK, but
  # proper coordination between the billing, product, and mobile teams must be done like was done for Copilot.
  class CancelInAppPurchasedSubscriptionItemJob < BillingJob
    extend T::Helpers
    include GitHub::Memoizer

    class CancellationError < StandardError; end

    # Used for datadog metrics and restraint locking
    KEY_PREFIX = "billing.cancel_in_app_purchased_subscription_item_job"

    sig { returns(T.nilable(Integer)) }
    attr_accessor :subscription_item_id

    retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10 do |job, error|
      Failbot.report(error, subscription_item_id: job.subscription_item_id)
    end

    sig { params(subscription_item_id: Integer).void }
    def perform(subscription_item_id)
      # This intended to be used when a GitHub::Restraint::UnableToLock error is raised
      @subscription_item_id = T.let(subscription_item_id, T.nilable(Integer))

      subscription_item = Billing::SubscriptionItem.find(subscription_item_id)

      # Scope the result variable outside the throttle block so we can assign it within the block and
      # access it outside after.
      result = T.let(nil, T.nilable(Billing::Public::SubscriptionItems::ResultStruct))

      Billing::SubscriptionItem.throttle_writes_with_retry(max_retry_count: 5) do
        lock(subscription_item) do
          # Make the call to cancel the subscription.
          # We are going to force it here to keep it synchronous within this classes execution flow.
          # Also notice the allow_cancelling_iap: true argument, this is key here to let our billing system
          # know that we understand the implications of cancelling an in-app purchased subscription.
          result = subscription_item.cancel!(force: true, allow_cancelling_iap: true)
        end
      end

      # Increment Datadog needle whether this was successful or not.
      GitHub.dogstats.increment(KEY_PREFIX, tags: ["cancelled:#{result&.result&.success || false}"])

      # Something went wrong within Billing, report this to Failbot.
      Failbot.report(
        CancellationError.new("Failed to cancel in-app purchased subscription item."),
        subscription_item_id: subscription_item.id,
        errors: result&.result&.errors || [],
      ) unless result&.result&.success

      nil
    end

    private

    # Internal: Use a GitHub::Restraint to prevent simultaneous updates
    sig do
      type_parameters(:R).params(
        subscription_item: Billing::SubscriptionItem,
        block: T.proc.params(arg0: GitHub::Restraint::Lock).returns(T.type_parameter(:R))
      ).void
    end
    def lock(subscription_item, &block)
      lock_key = "#{KEY_PREFIX}.#{subscription_item.id}"

      restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 5.minutes, &block)
    end

    sig { returns(GitHub::Restraint) }
    memoize def restraint
      GitHub::Restraint.new
    end
  end
end
