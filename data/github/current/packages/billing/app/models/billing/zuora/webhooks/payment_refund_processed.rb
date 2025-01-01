# typed: true
# frozen_string_literal: true

# Handler for PaymentRefundProcessed webhooks from Zuora
class Billing::Zuora::Webhooks::PaymentRefundProcessed < ::Billing::Zuora::Webhooks::WebhookHandler
  extend T::Sig

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

    if handle_side_effects_outside_transaction?
      refund_transaction.save!
      send_refund_email(
        refund_transaction: refund_transaction,
        sale_transaction: sale_transaction,
      )
      SponsorsProcessRefundJob.perform_later(
        refund_transaction: refund_transaction,
        sale_transaction: sale_transaction,
      ) if sale_transaction.sponsors_line_items.any?
    else
      ::Billing::BillingTransaction.transaction do
        refund_transaction.save!
        reverse_stripe_transfer if should_refund_sponsors_payment?
        send_refund_email(
          refund_transaction: refund_transaction,
          sale_transaction: sale_transaction,
        )
      end
    end
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

  sig { void }
  def reverse_stripe_transfer
    sale_transaction = T.must(self.sale_transaction)

    if sale_transaction.amount_in_cents != refund_amount_in_cents
      GitHub.logger.info(
        "Skipping reversal of Stripe transfer for partial refund",
        "code.namespace" => self.class.name,
        "code.function" => "reverse_stripe_transfer",
        "gh.billing.zuora.payment.id" => payment_id,
        "gh.billing.zuora.refund.id" => refund_id
      )

      return
    end

    ::Billing::Stripe::SaleTransfersReversal.perform(
      sale_transaction_id: sale_transaction.platform_transaction_id,
      stripe_refund_id: refund_transaction_id,
      zuora_refund_id: refund_id,
    )
  end

  # Check whether the sponsors listing has Stripe transfers enabled
  sig { returns(T::Boolean) }
  def should_refund_sponsors_payment?
    sale_transaction = T.must(self.sale_transaction)

    sale_transaction.line_items.sponsorships.preload(sponsors_tier: :sponsors_listing).any? do |sponsorship_line_item|
      tier = sponsorship_line_item.sponsors_tier
      tier&.listing&.stripe_transfers_enabled?
    end
  end

  sig { returns(String) }
  def refund_transaction_id
    zuora_refund["ReferenceID"]
  end

  sig { returns(Integer) }
  def refund_amount_in_cents
    (zuora_refund["Amount"] * 100).to_i
  end

  sig { returns T::Boolean }
  def handle_side_effects_outside_transaction?
    sale_transaction&.billable_entity&.feature_enabled?(:billing_refund_side_effects) || false
  end

  sig do
    params(
      refund_transaction: Billing::BillingTransaction,
      sale_transaction: Billing::BillingTransaction,
    ).void
  end
  def send_refund_email(refund_transaction:, sale_transaction:)
    custom_email_text = account_deleted? ? "This refund is the result of a cancelled subscription" : nil
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
