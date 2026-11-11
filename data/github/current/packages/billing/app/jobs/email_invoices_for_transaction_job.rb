# typed: strict
# frozen_string_literal: true

class EmailInvoicesForTransactionJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on GitHub::Restraint::UnableToLock,
    attempts: 3,
    wait: :polynomially_longer

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, EmailInvoicesForTransactionJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(transaction_id: Integer, emails: T::Array[String]).void }
  def perform(transaction_id:, emails:)
    transaction = Billing::BillingTransaction.find_by(id: transaction_id)
    platform_transaction_id = transaction&.platform_transaction_id

    unless platform_transaction_id
      GitHub.logger.info(
        "Skipping invoice email: no platform transaction found",
        "code.namespace" => self.class.name,
        "gh.billing.transaction.id" => transaction_id,
      )
      return
    end

    billable_entity = transaction.billable_entity
    if billable_entity.nil? || billable_entity.is_a?(Billing::DeadUser)
      GitHub.logger.info(
        "Skipping invoice email: billable entity missing or deleted",
        "code.namespace" => self.class.name,
        "gh.billing.transaction.id" => transaction_id,
        "gh.billing.zuora.transaction.id" => platform_transaction_id,
      )
      return
    end

    invoices = Billing::Zuora::Invoice.invoices_for_transaction(platform_transaction_id, billable_entity:)
    joined_emails = emails.join(",")

    if invoices.empty?
      GitHub.logger.info(
        "No invoices found for transaction; skipping invoice email",
        "code.namespace" => self.class.name,
        "gh.billing.transaction.id" => transaction_id,
        "gh.billing.zuora.transaction.id" => platform_transaction_id,
        "gh.billing.billable_entity.id" => billable_entity.id,
        "gh.billing.billable_entity.login" => billable_entity.display_login,
        "gh.billing.billable_entity.type" => billable_entity.class.name,
      )
      return
    end

    GitHub.logger.info(
      "Sending invoice emails for transaction",
      "code.namespace" => self.class.name,
      "gh.billing.transaction.id" => transaction_id,
      "gh.billing.zuora.transaction.id" => platform_transaction_id,
      "gh.billing.billable_entity.id" => billable_entity.id,
      "gh.billing.billable_entity.login" => billable_entity.display_login,
      "gh.billing.billable_entity.type" => billable_entity.class.name,
      "gh.billing.zuora.invoice.count" => invoices.size,
      "gh.billing.zuora.email.recipient_count" => emails.size,
    )

    invoices.each do |invoice|
      EmailInvoiceJob.perform_later(invoice_id: invoice.id, emails: joined_emails)
    end
  end
end
