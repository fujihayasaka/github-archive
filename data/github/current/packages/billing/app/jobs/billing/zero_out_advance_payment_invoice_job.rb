# typed: strict
# frozen_string_literal: true

class Billing::ZeroOutAdvancePaymentInvoiceJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, Billing::ZeroOutAdvancePaymentInvoiceJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(customer_id: Integer, idempotency_key: T.nilable(String), invoice_id: T.nilable(String)).void }
  def perform(customer_id:, idempotency_key: nil, invoice_id: nil)
    customer = ::Customer.find(customer_id)

    if idempotency_key.present?
      advance_payment = ::Billing::AdvancePayment.new(customer:, idempotency_key:)
      with_write { advance_payment.cleanup_orphaned_invoice! }
    elsif invoice_id.present?
      with_write { ::Billing::AdvancePayment.cancel_pending_invoice!(customer:, invoice_id:) }
    end
  end
end
