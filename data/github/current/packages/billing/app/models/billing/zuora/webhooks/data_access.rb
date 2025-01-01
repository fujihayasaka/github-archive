# typed: strict
# frozen_string_literal: true

module Billing::Zuora::Webhooks::DataAccess
  # Common methods for accessing Zuora data in Zuora webhooks
  extend T::Helpers

  include GitHub::Memoizer

  requires_ancestor { ::Billing::Zuora::Webhooks::WebhookHandler }

  # Internal: The user's Zuora account
  sig { returns(T.nilable(Zuorest::Model::Account)) }
  memoize def zuora_account
    customer.zuora_account
  end

  # Internal: The Zuora invoice referenced in this webhook
  #
  sig { returns(Billing::Zuora::Invoice) }
  memoize def zuora_invoice
    ::Billing::Zuora::Invoice.new(invoice_id)
  end

  # Internal: The Zuora payment referenced in this webhook
  sig { returns(Billing::Zuora::Payment) }
  memoize def zuora_payment
    ::Billing::Zuora::Payment.find(payment_id)
  end

  # Internal: The Zuora credit balance adjustment referenced in this
  # webhook's Zuora invoice, if any.
  sig { returns(T.nilable(Billing::Zuora::CreditBalanceAdjustment)) }
  memoize def zuora_credit_balance_adjustment
    if zuora_credit_balance_adjustment_id.present?
      ::Billing::Zuora::CreditBalanceAdjustment.find(zuora_credit_balance_adjustment_id)
    end
  end
  delegate :zuora_credit_balance_adjustment_id, to: :zuora_invoice

  # Internal: The Zuora refund referenced in this webhook
  sig { returns(T::Hash[String, T.untyped]) }
  memoize def zuora_refund
    ::GitHub.zuorest_client.get_refund(refund_id)
  end

  # Internal: The user's Zuora subscription
  #
  sig { returns(T.nilable(Billing::Zuora::Subscription)) }
  memoize def zuora_subscription
    plan_subscription.zuora_subscription
  end

  sig { returns(T.nilable(Billing::Zuora::Subscription)) }
  def zuora_subscription_with_fallback
    zuora_subscription || zuora_subscription_from_invoice
  end

  sig { returns(T.nilable(Billing::Zuora::Subscription)) }
  memoize def zuora_subscription_from_invoice
    invoice_items = zuora_payment.invoice_items
    item_with_subscription = invoice_items.detect(&:subscription_number)
    Billing::Zuora::Subscription.find(item_with_subscription&.subscription_number)
  end
end
