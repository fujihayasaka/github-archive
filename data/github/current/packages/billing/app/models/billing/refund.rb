# typed: true
# frozen_string_literal: true

class Billing::Refund
  attr_reader :sale_transaction, :refund_invoice_payment_data

  # Refund a transaction
  #
  # sale_transaction - Billing::BillingTransaction
  def initialize(sale_transaction, refund_invoice_payment_data: nil)
    @sale_transaction = sale_transaction
    @refund_invoice_payment_data = refund_invoice_payment_data
  end

  # Refund a transaction
  #
  # refund_amount_in_cents - Integer cents to refund.
  #
  # Returns a Result object
  def process(refund_amount_in_cents)
    if sale_transaction.legacy_braintree?
      return GitHub::Billing::Result.failure("Cannot refund legacy transaction")
    end

    if sale_transaction.credit_balance_adjustment_transaction?
      return GitHub::Billing::Result.failure("Cannot refund a credit balance transaction")
    end

    if sale_transaction.zuora?
      process_with_zuora(refund_amount_in_cents)
    else
      process_with_braintree(refund_amount_in_cents)
    end
  end

  private

  def log_refund(refund_amount_in_cents, braintree_refund_transaction)
    refund_transaction = sale_transaction.dup
    refund_transaction.update \
      amount_in_cents: -1 * refund_amount_in_cents,
      transaction_type: "refund",
      sale_transaction_id: sale_transaction.transaction_id,
      transaction: braintree_refund_transaction,
      old_plan_name: sale_transaction.plan_name,
      plan_name: refund_transaction.user.try(:plan).try(:name)

    refund_transaction
  end

  def process_with_zuora(refund_amount_in_cents)
    ::Billing::ZuoraRefund
      .process(sale_transaction, ::Billing::Money.new(refund_amount_in_cents), refund_invoice_payment_data)
  end

  def process_with_braintree(refund_amount_in_cents)
    begin
      sale_transaction_id = sale_transaction.transaction_id
      result = GitHub.dogstats.time("braintree.timing.transaction_refund") do
        Braintree::Transaction.refund(sale_transaction_id, ::Billing::Money.new(refund_amount_in_cents).to_s)
      end

      if result.success?
        refund = log_refund(refund_amount_in_cents, result.transaction)

        GitHub.dogstats.increment("billing.refund")
        GitHub::Billing::Result.success(refund)
      else
        GitHub::Billing::Result.failure(result.message)
      end
    rescue Braintree::NotFoundError
      GitHub::Billing::Result.failure("Transaction not found: #{sale_transaction_id}")
    end
  end
end
