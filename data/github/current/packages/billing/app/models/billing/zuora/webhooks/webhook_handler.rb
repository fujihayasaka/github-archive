# typed: strict
# frozen_string_literal: true


# We can't turn this into strict yet because prepend is not supported by sorbet
class Billing::Zuora::Webhooks::WebhookHandler
  include ::Billing::Zuora::Webhooks::DataAccess

  # Reference: https://github.com/stimulusreflex/stimulus_reflex/pull/160
  sig { params(subclass: T.class_of(Billing::Zuora::Webhooks::WebhookHandler)).void }
  def self.inherited(subclass)
    subclass.prepend(Billing::Zuora::Webhooks::Callbacks)
  end

  sig { params(webhook: ::Billing::ZuoraWebhook).returns(T::Boolean) }
  def self.perform(webhook)
    new(webhook).perform
  end

  NOT_PROCESSED = "Zuora subscription not synched, cannot process payment"

  sig { returns(::Billing::ZuoraWebhook) }
  attr_reader :webhook

  sig { params(webhook: ::Billing::ZuoraWebhook).void }
  def initialize(webhook)
    @webhook = webhook
  end

  protected

  sig { returns(T.nilable(::Billing::Types::Account)) }
  def account
    webhook.account
  end

  delegate :account_deleted?,
           :account_id,
           :account_suspended?,
           :business_account?,
           :customer,
           :invoice_id,
           :payload,
           :payment_id,
           :plan_subscription,
           :refund_id,
           :subscription_id,
           :user_account?,
           to: :webhook

  delegate :payment_method,
           to: :customer,
           allow_nil: true

  sig { returns(T::Boolean) }
  def perform
    raise "Not implemented"
  end

  sig { returns(T::Boolean) }
  def account_deleted_or_suspended?
    account_deleted? || account_suspended?
  end

  sig { returns(T::Boolean) }
  def already_processed_transaction?
    return false unless account = self.account

    transaction_id = zuora_payment.reference_id || zuora_payment.payment_number
    account.billing_transactions.for_transaction(transaction_id).any?
  end

  # Throwing :abort will cause the callback chain to halt
  sig { void }
  def ignore!
    throw :abort
  end

  sig { void }
  def ensure_zuora_subscription_exists
    return if plan_subscription.zuora_subscription_number?

    GitHub.dogstats.increment(
      "billing.missing_zuora_subscription.count",
      tags: ["class:#{self.class.name.to_s.underscore}"]
    )

    raise NOT_PROCESSED unless plan_subscription.synchronize_with_lock.success?
  end
end
