# typed: strict
# frozen_string_literal: true

class EmailInvoicesForTransactionJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :billing

  retry_on GitHub::Restraint::UnableToLock,
    attempts: 3,
    wait: :polynomially_longer

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, SyncZuoraTaxExemptStatusJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(transaction_id: Integer, emails: T::Array[String]).void }
  def perform(transaction_id:, emails:)
    transaction = Billing::BillingTransaction.find_by(id: transaction_id)
    platform_transaction_id = transaction&.platform_transaction_id
    return unless platform_transaction_id

    billable_entity = transaction.billable_entity
    return if billable_entity.nil? || billable_entity.is_a?(Billing::DeadUser)

    Billing::Zuora::Invoice.invoices_for_transaction(platform_transaction_id, billable_entity:).each do |invoice|
      EmailInvoiceJob.perform_later(invoice_id: invoice.id, emails: emails.join(","))
    end
  end
end
