# typed: true
# frozen_string_literal: true

class SponsorsProcessRefundJob < ApplicationJob
  retry_on_dirty_exit

  queue_as :sponsors_process_refund

  sig do
    params(
      refund_transaction_id: Integer,
      sale_transaction_id: Integer,
    ).void
  end
  def perform(refund_transaction_id:, sale_transaction_id:)
    return unless GitHub.sponsors_enabled?

    refund_transaction = Billing::BillingTransaction.find_by(id: refund_transaction_id)
    return unless refund_transaction

    sale_transaction = Billing::BillingTransaction.find_by(id: sale_transaction_id)
    return unless sale_transaction

    return unless should_refund_sponsors_payment?(sale_transaction)

    refund_amount_in_cents = refund_transaction.amount_in_cents.abs
    sale_amount_in_cents = sale_transaction.amount_in_cents

    # Skip partial refunds
    if sale_amount_in_cents != refund_amount_in_cents
      GitHub.logger.info(
        "Skipping reversal of Stripe transfer for partial refund",
        "code.namespace": self.class.name,
        "code.function": "perform",
        "gh.billing.sale_transaction.id": sale_transaction.id,
        "gh.billing.refund_transaction.id": refund_transaction.id
      )
      return
    end

    # Perform the Stripe transfer reversal
    ::Billing::Stripe::SaleTransfersReversal.perform(
      sale_transaction_id: sale_transaction.platform_transaction_id,
      stripe_refund_id: refund_transaction.transaction_id,
      zuora_refund_id: refund_transaction.platform_transaction_id,
    )
  end

  private

  # Check whether the sponsors listing has Stripe transfers enabled
  sig { params(sale_transaction: Billing::BillingTransaction).returns(T::Boolean) }
  def should_refund_sponsors_payment?(sale_transaction)
    sale_transaction.line_items.sponsorships.preload(sponsors_tier: :sponsors_listing).any? do |sponsorship_line_item|
      tier = sponsorship_line_item.sponsors_tier
      tier&.listing&.stripe_transfers_enabled?
    end
  end
end
