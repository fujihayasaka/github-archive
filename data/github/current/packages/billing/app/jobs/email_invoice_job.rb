# typed: strict
# frozen_string_literal: true

class EmailInvoiceJob < BillingJob
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
    T.bind(self, SyncZuoraTaxExemptStatusJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(invoice_id: String, emails: String).void }
  def perform(invoice_id:, emails:)
    response = GitHub.zuorest_client.email_invoice(invoice_id, { emailAddresses: emails }, { "Content-Type" => "application/json" })
    result = GitHub::Billing::Result.from_zuora(response)
    unless result.success?
      GitHub.logger.error(
        "Failed to email Zuora invoice",
        "code.namespace" => self.class.name,
        "gh.billing.zuora.invoice.ids" => invoice_id,
        "gh.billing.zuora.response.success" => result.success?,
        "gh.billing.zuora.response.error_message" => result.error_message,
        "gh.billing.zuora.response.request_id" => response["requestId"],
      )
      GitHub.dogstats.increment("billing.email_zuora_invoice_job.email_invoice_failure")
    end
  end
end
