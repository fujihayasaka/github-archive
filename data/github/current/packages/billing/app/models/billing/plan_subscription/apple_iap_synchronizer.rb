# typed: strict
# frozen_string_literal: true

module Billing
  class PlanSubscription::AppleIapSynchronizer
    sig { params(subscription: Billing::PlanSubscription).returns(T.attached_class) }
    def self.call(subscription)
      new(subscription).call
    end

    sig { params(subscription: Billing::PlanSubscription).void }
    def initialize(subscription)
      @subscription = subscription
      @user = T.let(T.must(subscription.user), User)
      @error_message = T.let("", String)
    end

    sig { returns(T.self_type) }
    def call
      subscription_summary = retrieve_status

      # There are three cases we want to cancel accounts for. If it passes all these checks then
      # we can assume the subscription is valid and should be kept.
      if subscription_summary.nil?
        # We do not have a receipt so treat it like it is invalid
        clear_subscription!
        @error_message = "Apple receipt is not valid."
      elsif !subscription_summary.production? || @subscription.plan.free?
        # Always cancel sandbox subscriptions and free subscriptions
        clear_subscription!
      elsif !subscription_summary.pro?
        # Cancel the subscription if it is cancellable (apple said it was cancelled or should be cancelled)
        @user.update!(plan: GitHub::Plan.free) if @user.plan.pro?
        clear_subscription!
      end

      self
    end

    sig { returns(T::Boolean) }
    def success?
      @error_message.blank?
    end

    sig { returns(String) }
    def error_message
      @error_message
    end

    private

    sig { void }
    def clear_subscription!
      @subscription.update!(apple_receipt_id: nil, apple_transaction_id: nil)
    end

    # The new implementation backed by Apple's StoreKit API
    sig { returns(T.nilable(Mobile::Apple::SubscriptionSummary)) }
    def retrieve_status
      original_transaction_id = @subscription.apple_transaction_id

      # Nothing we can do without a transaction ID
      return if original_transaction_id.blank?

      begin
        Mobile::Apple::AppStoreService.from_config.get_subscription_summary(original_transaction_id:)
      rescue Mobile::Apple::AppStoreClient::InvalidTransactionIdError => ex
        # Match existing functionality by returning null when Apple returns a not found transaction status.
      end
    end
  end
end
