# typed: strict
# frozen_string_literal: true

module Billing
  class SubscriptionItem
    # This class is able to properly synchronize in-app purchased SubscriptionItem records with Apple.
    # It will call Apple's StoreKit API and check the status of the susbcription using the original transaction ID
    # stored on the apple_subscriptions extension table (Billing::AppleSubscription model). Our StoreKit API
    # service and client understand how to do the dirty work here and return us a SubscriptionSummary object
    # which this class can then act against: SubscriptionSummary basically says: "for this transaction I see these
    # active subscriptions on the Apple side". When this reports back a status of not-active (expired, cancelled, etc.)
    # then we will cancel the SubscriptionItem record in our system using this class.
    #
    # This class is meant to be a synchronous process (no pun intended). If the intention is to execute this as a
    # background job then the caller call this in a job class and enqueue it.
    #
    # This class is extemely similar to the existing Billing::PlanSubscription::AppleIapSynchronizer class
    # but the difference is that class synchronizes Pro subscriptions with our Billing::PlanSubscription
    # record/model while this one synchronizes SubscriptionItem record/models. In the future, we may want to
    # look to consolidate these two synchronization classes which can allow us to make less calls to
    # Apple (less network chatter == better) but for now, we can keep them independent and leave consolidation
    # as a separate project.
    class IapSynchronizer

      # The reason Apple gave us for cancelling the subscription item.
      class CancellationReason < T::Enum
        enums do
          # Apple did not find the transaction ID on their side.
          NOT_FOUND = new

          # We always cancel sandbox receipts. Think of this more like a cleanup process.
          SANDBOX = new

          # Apple told us the subscription item is inactive (probably because it was cancelled by the user or expired.)
          EXPIRED = new

          # Apple told us that the subscription item is Pro but we detected that the user is on a Pro+ plan.
          DOWNGRADED = new
        end
      end

      # Wrap up the result of a single synchronization process.
      class Result < T::Struct

        # The reason Apple gave us for cancelling the subscription item.
        const :cancellation_reason, T.nilable(CancellationReason)

        # The underlying result of the subscription item cancellation process.
        const :subscription_item_result, T.nilable(Billing::Public::SubscriptionItems::ResultStruct)

        # Whether or not the subscription item was cancelled during the sync process.
        sig { returns(T::Boolean) }
        def cancelled?
          cancellation_reason.present?
        end

        # Determines if the overall sync process was successful or not. It is successful if we are not cancelling
        # the item or if the underlying cancellation process succeeds.
        sig { returns(T::Boolean) }
        def success?
          # If we aren't cancelling then we are good to go.
          return true unless cancelled?

          # If we are cancelling then we need to check the result of the subscription item cancellation
          # to determine if the cancellation was successful.
          # This will fall back to false if, for whatever reason, the subscription_item return is null.
          subscription_item_result&.result&.success || false
        end

        # Returns an array of error messages from the underlying subscription item cancellation result.
        # This will be empty for non-cancellation results or if the cancellation succeeded.
        sig { returns(T::Array[String]) }
        def errors
          subscription_item_result&.result&.errors || []
        end
      end

      # Top class-level entry point to synchronize a single SubscriptionItem record.
      sig { params(subscription_item: SubscriptionItem).returns(Result) }
      def self.call(subscription_item)
        new(subscription_item).call
      end

      # This class is a composite object for this SubscriptionItem instance.
      sig { returns(SubscriptionItem) }
      attr_reader :subscription_item

      # Initialization will fail if the passed-in SubscriptionItem record was not in-app purchased. There is nothing
      # this class could/should do for non-IAP SubscriptionItem objects.
      sig { params(subscription_item: SubscriptionItem).void }
      def initialize(subscription_item)
        raise ArgumentError, "Must have an associated in-app purchase record to sync." unless subscription_item.in_app_purchase?

        @subscription_item = subscription_item
        @app_store_service = T.let(Mobile::Apple::AppStoreService.from_config, Mobile::Apple::AppStoreService)
        @restraint = T.let(GitHub::Restraint.new, GitHub::Restraint)

        @copilot_subscription_item = T.let(
          Public::InAppPurchasing::CopilotSubscriptionItem.new(subscription_item),
          Public::InAppPurchasing::CopilotSubscriptionItem
        )
      end

      # Main instance-level method which handles the actual synchronization process.
      # Note that this will lock the SubscriptionItem record to prevent simulataneous updates so there
      # is a chance this could raise a GitHub::Restraint::UnableToLock error.
      sig { returns(Result) }
      def call
        subscription_summary = retrieve_status
        cancellation_reason = derive_cancellation_reason(subscription_summary)

        # Short-circuit since we found out we do not have to cancel this subscription.
        # Default Result object is setup to return an "active state" response so we do not have to
        # construct it with any additional arguments.
        return Result.new if cancellation_reason.blank?

        # Establish the scope of this variable here so we can reference it in the lock block.
        subscription_item_result = T.let(nil, T.nilable(Billing::Public::SubscriptionItems::ResultStruct))

        # This will minimize the locking time to _only_ account for the actual mutable cancellation process.
        # The locking key will be in the format: billing.iap_synchronizer.#{subscription_item.id}
        lock do
          if cancellation_reason == CancellationReason::DOWNGRADED
            subscription_item_result = copilot_subscription_item.downgrade_pro_plus
          else
            # Any other cancellation reason currently means we are going to cancel the subscription item.
            subscription_item_result = copilot_subscription_item.cancel
          end
        end

        Result.new(cancellation_reason:, subscription_item_result:)
      end

      private

      # Internal: An instance of this class helps us act within GitHub's billing context but also within the
      # context of in-app purchases. We can leverage this for plan type detection, cancellation, and downgrading
      # within the explicit context of in-app purchases.
      sig { returns(Public::InAppPurchasing::CopilotSubscriptionItem) }
      attr_reader :copilot_subscription_item

      # Internal: An instance to the Apple StoreKit API service/client we want to use to synchronize with.
      sig { returns(Mobile::Apple::AppStoreService) }
      attr_reader :app_store_service

      # Internal: A GitHub::Restraint instance we want to use to lock the SubscriptionItem record.
      sig { returns(GitHub::Restraint) }
      attr_reader :restraint

      # Internal: This method interprets what Apple sends us back that we wrap up in a SubscriptionSummary object.
      # Based on the SupscriptionSummary object, this method will give you back the reason why the
      # SubscriptionItem record should be cancelled. If the return is a blank string then the SubscriptionItem
      # is active and should not be cancelled.
      #
      # Important note: This is currently coded to only support Copilot subscriptions. If we intend to support
      # other SKUs via IAP then we need to generalize this a bit more and properly map Apple SKUS -> GitHub SKUs.
      sig do
        params(subscription_summary: T.nilable(Mobile::Apple::SubscriptionSummary))
          .returns(T.nilable(CancellationReason))
      end
      def derive_cancellation_reason(subscription_summary)
        return CancellationReason::NOT_FOUND if subscription_summary.nil?
        return CancellationReason::SANDBOX if !subscription_summary.production?

        # Special Note: Right now this is hard-coded to only support copilot subscriptions as
        # SubscriptionItems capable of IAP. This will need to be made more generic / modified if
        # we ever support other types of products available for IAP.

        # This can be interpreted as: Apple says the user should be on Pro but GitHub currently says the
        # user is on Pro+.
        if subscription_summary.copilot? && copilot_subscription_item.pro_plus?
          CancellationReason::DOWNGRADED
        elsif !subscription_summary.copilot? && !subscription_summary.copilot_pro_plus?
          CancellationReason::EXPIRED
        else
          # Any other case here means: do nothing, the subscriptions match and is still active.
          nil
        end
      end

      #  Internal:  Calls out Apple StoreKit API service/client to retrieve the status of the subscription
      # and returns back a summary of all active subscriptions.
      sig { returns(T.nilable(Mobile::Apple::SubscriptionSummary)) }
      def retrieve_status
        apple_subscription = T.must(subscription_item.apple_subscription)
        original_transaction_id = apple_subscription.original_transaction_id

        app_store_service.get_subscription_summary(original_transaction_id:)
      rescue Mobile::Apple::AppStoreClient::InvalidTransactionIdError => ex
        # return null if Apple told us the transaction ID is invalid.
        nil
      rescue Mobile::Apple::AppStoreClient::TransactionIdNotFoundError => ex
        # return null if Apple told us the transaction ID was not found.
        nil
      end

      # Internal: Use a GitHub::Restraint to prevent simultaneous updates
      sig do
        type_parameters(:R).params(
          block: T.proc.params(arg0: GitHub::Restraint::Lock).returns(T.type_parameter(:R))
        ).void
      end
      def lock(&block)
        lock_key = "billing.iap_synchronizer.#{subscription_item.id}"

        restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 5.minutes, &block)
      end
    end
  end
end
