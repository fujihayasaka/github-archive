# typed: strict
# frozen_string_literal: true

module Billing
  class SubscriptionItem
    # This class is able to properly synchronize in-app purchased SubscriptionItem records with Google.
    # It will call Google's Play Store Developer API and check the status of the susbcription using the purchase token
    # stored on the google_subscriptions extension table (Billing::GoogleSubscription model). Our Play Store client
    # understand how to do the dirty work here and return us a SubscriptionPurchase object
    # which this class can then act against: SubscriptionPurchase basically says: "the subscription that belongs to this
    # purchase token is active and in production environment". When this reports back a status of not-active (expired, cancelled, etc.)
    # then we will cancel the SubscriptionItem record in our system using this class.
    #
    # This class is meant to be a synchronous process (no pun intended). If the intention is to execute this as a
    # background job then the caller call this in a job class and enqueue it.
    class GoogleIapSynchronizer
      extend T::Sig

      # The reason Apple gave us for cancelling the subscription item.
      class CancellationReason < T::Enum
        enums do
          # Google did not find the purchase token on their side.
          NOT_FOUND = new

          # We always cancel test environment subscriptions. Think of this more like a cleanup process.
          TEST = new

          # Google told us the subscription item is inactive (probably because it was cancelled by the user or expired.)
          EXPIRED = new
        end
      end

      # Wrap up the result of a single synchronization process.
      class Result < T::Struct
        extend T::Sig

        # The reason Google gave us for cancelling the subscription item.
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
        @play_store_service = T.let(Mobile::Google::PlayStoreService.from_config, Mobile::Google::PlayStoreService)
        @restraint = T.let(GitHub::Restraint.new, GitHub::Restraint)
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
          # Make the call to cancel the subscription.
          # We are going to force it here to keep it synchronous within this classes execution flow.
          subscription_item_result = subscription_item.cancel!(force: true, allow_cancelling_iap: true)
        end

        Result.new(cancellation_reason:, subscription_item_result:)
      end

      private

      # Internal: An instance to the Play Store client we want to use to synchronize with.
      sig { returns(Mobile::Google::PlayStoreService) }
      attr_reader :play_store_service

      # Internal: A GitHub::Restraint instance we want to use to lock the SubscriptionItem record.
      sig { returns(GitHub::Restraint) }
      attr_reader :restraint

      # Internal: This method interprets what Play Store client sends us back that we wrap up in a SubscriptionPurchase object.
      # Based on the SubscriptionPurchase object, this method will give you back the reason why the
      # SubscriptionItem record should be cancelled. If the return is a blank string then the SubscriptionItem
      # is active and should not be cancelled.
      #
      # Important note: This is currently coded to only support Copilot subscriptions. If we intend to support
      # other SKUs via IAP then we need to generalize this a bit more and properly map Google SKUS -> GitHub SKUs.
      sig do
        params(subscription_purchase_summary: T.nilable(Mobile::Google::SubscriptionPurchaseSummary))
          .returns(T.nilable(CancellationReason))
      end
      def derive_cancellation_reason(subscription_purchase_summary)
        return CancellationReason::NOT_FOUND if subscription_purchase_summary.nil?
        return CancellationReason::TEST if !subscription_purchase_summary.environment.production?

        # Special Note: Right now this is hard-coded to only support copilot subscriptions as
        # SubscriptionItems capable of IAP. This will need to be made more generic / modified if
        # we ever support other types of products available for IAP.
        return CancellationReason::EXPIRED if subscription_purchase_summary.active_copilot_purchase_token.nil?

        # Returning null here means we do not have to cancel the subscription.
        nil
      end

      #  Internal:  Calls out Google Play Store API service/client to retrieve the status of the subscription
      # and returns back a summary of all active subscriptions.
      sig { returns(T.nilable(Mobile::Google::SubscriptionPurchaseSummary)) }
      def retrieve_status
        google_subscription = T.must(subscription_item.google_subscription)
        purchase_token = google_subscription.purchase_token

        play_store_service.get_subscription_purchase_summary(purchase_token:, product_id: Mobile::Google::COPILOT_MONTHLY_SKU_ID)
      rescue Mobile::Google::PlayStoreService::PurchaseNotFoundError => ex
        # return null if Google told us the purchase can not be found.
        nil
      end

      # Internal: Use a GitHub::Restraint to prevent simultaneous updates
      sig do
        type_parameters(:R).params(
          block: T.proc.params(arg0: GitHub::Restraint::Lock).returns(T.type_parameter(:R))
        ).void
      end
      def lock(&block)
        lock_key = "billing.google_iap_synchronizer.#{subscription_item.id}"

        restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 5.minutes, &block)
      end
    end
  end
end
