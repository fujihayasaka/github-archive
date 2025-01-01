# typed: strict
# frozen_string_literal: true

module Billing
  # Applies the dunning rules to the given account. This allows us to increment
  # the billing attempts appropriately with our concept of billing attempts until
  # we switch over to Braintree's failure count.  This also checks to see if there
  # are additional actions to perform on the account, like disabling and
  # sending out the appropriate notification.
  class DunSubscription
    extend T::Sig

    sig do
      params(
        account: ::Billing::Types::Account,
        message: T.nilable(String),
        braintree_subscription: T.nilable(::Braintree::Subscription),
        braintree_transaction: T.nilable(::Braintree::Transaction),
        skip_notification: T::Boolean
      ).void
    end
    def self.perform(account, message: nil, braintree_subscription: nil, braintree_transaction: nil, skip_notification: false)
      new(account, message: message, braintree_subscription: braintree_subscription, braintree_transaction: braintree_transaction, skip_notification: skip_notification).perform
    end

    sig { returns(::Billing::Types::Account) }
    attr_reader :account

    sig { returns(T.nilable(::Braintree::Subscription)) }
    attr_reader :braintree_subscription

    sig { returns(T.nilable(::Braintree::Transaction)) }
    attr_reader :braintree_transaction

    sig { returns(T.nilable(String)) }
    attr_reader :message

    sig { returns(T::Boolean) }
    attr_reader :skip_notification

    # account                 - User/Organization/Business that needs to be disabled
    #
    # message                 - An optional String to pass in as the error message.
    # braintree_transaction:  - An optional Braintree::Transaction. Passed in from the BrainTree
    #                           webhook as the 'relevant transaction' see
    #                           app/models/billing/plan_subscription/braintree_webhook.rb
    sig do
      params(
        account: ::Billing::Types::Account,
        message: T.nilable(String),
        braintree_subscription: T.nilable(::Braintree::Subscription),
        braintree_transaction: T.nilable(::Braintree::Transaction),
        skip_notification: T::Boolean
      ).void
    end
    def initialize(account, message: nil, braintree_subscription: nil, braintree_transaction: nil, skip_notification: false)
      @account                = account
      @braintree_subscription = braintree_subscription
      @braintree_transaction  = braintree_transaction
      @plan_subscription      = T.let(account.plan_subscription, T.nilable(::Billing::PlanSubscription))
      @message                = T.let(message || error_message, T.nilable(String))
      @skip_notification      = skip_notification
    end

    sig { void }
    def perform
      dun_subscription!
      send_notification! unless skip_notification
    end

    private

    # Private: Apply the dunning rules to the subscription and determine
    # if the account should remain enabled or disabled.
    sig { void }
    def dun_subscription!
      # NB: This uses the old behavior to replace a 0 value with 1 billing attempt.
      # This was probably to safeguard any calls to this as a first attempt.
      # (see https://github.com/github/github/blob/ac80608e/app/models/billing/plan_subscription/disable_account.rb#L44
      # compare
      if account.billing_attempts.to_i == 0
        account.set_billing_attempts(1)
      end

      if account.disabled?
        Billing::CancelPastDueProductsJob.perform_later(billable_entity: account, caller: self.class.name)
      else
        account.enable_or_disable!
      end

      return if account.feature_enabled?(:billing_only_cancel_past_due_products)

      if account.disabled?
        if account.any_external_subscriptions?
          T.must(account.customer).cancel_external_subscriptions
        end
      end
    end

    # Private: Sends a notification about why the account was disabled.
    sig { void }
    def send_notification!
      if account.billing_attempts == 1 || account.billing_attempts == 2
        if account.has_credit_card?
          if account.card_expired?
            BillingNotificationsMailer.cc_expired_failure(account).deliver_later
            increment_dunning_notification_metric("cc_expired_failure")
          else
            BillingNotificationsMailer.cc_failure(account, message.to_s).deliver_later
            increment_dunning_notification_metric("cc_failure")
          end
        elsif account.has_paypal_account?
          BillingNotificationsMailer.paypal_failure(account, message.to_s).deliver_later
          increment_dunning_notification_metric("paypal_failure")
        else
          BillingNotificationsMailer.no_payment_failure(account).deliver_later
          increment_dunning_notification_metric("no_payment_failure")
        end
      elsif account.over_billing_attempts_limit?
        BillingNotificationsMailer.over_billing_attempts_limit_failure(account, message.to_s).deliver_later
        increment_dunning_notification_metric("over_billing_attempts_limit_failure")
      end
    end

    sig { params(notification_type: String).void }
    def increment_dunning_notification_metric(notification_type)
      GitHub.dogstats.increment "billing.dunning_subscription.notify",
        tags: ["notification_type:#{notification_type}", "attempts:#{account.billing_attempts}"]
    end

    # Private: The error message displayed to the User (in email) when their
    # subscription payment fails.
    sig { returns(String) }
    def error_message
      braintree_transaction = self.braintree_transaction
      if braintree_transaction && braintree_transaction.processor_response_text.present?
        braintree_transaction.processor_response_text
      else
        "Call your payment provider to resolve this issue."
      end
    end
  end
end
