# typed: true
# frozen_string_literal: true

# Handler for PaymentRefundProcessed webhooks from Zuora
class Billing::Zuora::Webhooks::PaymentRefundProcessed < ::Billing::Zuora::Webhooks::WebhookHandler
  before_perform :ignore!, if: -> do
    T.bind(self, Billing::Zuora::Webhooks::PaymentRefundProcessed)

    no_sale_transaction? || already_refunded_transaction?
  end

  after_perform :instrument_processed_refund

  include GitHub::Memoizer

  def perform
    sale_transaction = T.must(self.sale_transaction)

    refund_transaction = sale_transaction.build_refund_transaction(
      amount_in_cents: refund_amount_in_cents,
      platform_transaction_id: refund_id,
      refund_reference_id: refund_transaction_id
    )

    refund_transaction.save!

    send_refund_email(
      refund_transaction: refund_transaction,
      sale_transaction: sale_transaction,
    )

    SponsorsProcessRefundJob.perform_later(
      refund_transaction_id: refund_transaction.id,
      sale_transaction_id: sale_transaction.id,
    ) if sale_transaction.sponsors_line_items.any?
  end

  private

  sig { returns(T::Boolean) }
  def no_sale_transaction?
    sale_transaction.blank?
  end

  sig { returns(T::Boolean) }
  def already_refunded_transaction?
    ::Billing::BillingTransaction.exists?(transaction_id: refund_transaction_id)
  end

  sig { returns(String) }
  def refund_transaction_id
    zuora_refund["ReferenceID"]
  end

  sig { returns(Integer) }
  def refund_amount_in_cents
    (zuora_refund["Amount"] * 100).to_i
  end

  sig do
    params(
      refund_transaction: Billing::BillingTransaction,
      sale_transaction: Billing::BillingTransaction,
    ).void
  end
  def send_refund_email(refund_transaction:, sale_transaction:)
    custom_email_text =
      if account_deleted?
        "This refund is the result of a cancelled subscription"
      else
        sale_transaction.email_refund_custom_text
      end

    sale_transaction.create_refund_email(
      refund_transaction: refund_transaction,
      refund_amount_in_cents: refund_amount_in_cents,
      email_refund_custom_text: custom_email_text
    ).deliver_now
  end

  sig { returns(T.nilable(::Billing::BillingTransaction)) }
  memoize def sale_transaction
    ::Billing::BillingTransaction.find_by(platform_transaction_id: payment_id)
  end

  sig { void }
  def instrument_processed_refund
    ::GitHub.dogstats.increment("billing.refund")
  end
end
