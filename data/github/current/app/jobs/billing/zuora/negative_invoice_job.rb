# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class Billing::Zuora::NegativeInvoiceJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler

  queue_as :billing

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RETRYABLE_ERRORS = T.let(::Billing::Zuora::RETRYABLE_ERRORS + [
    GitHub::Restraint::UnableToLock
  ].freeze, T::Array[T.class_of(StandardError)])

  RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, Billing::Zuora::NegativeInvoiceJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(invoice_id: String).void }
  def perform(invoice_id:)
    invoice = ::Billing::Zuora::Invoice.new(invoice_id)

    Billing::Zuora::Invoice.record_metrics(
      balance_in_cents: invoice.balance * 100,
      calling_class: "negative_invoice_job",
    )

    return unless invoice.balance.negative?

    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.billing.zuora.invoice.id" => invoice_id,
      "gh.billing.zuora.invoice.number" => invoice.number,
      "gh.billing.zuora.invoice.amount" => invoice.amount,
      "gh.billing.zuora.invoice.balance" => invoice.balance
    )

    Billing::Zuora::ZeroOutInvoice.run(invoice: invoice)
  end
end
