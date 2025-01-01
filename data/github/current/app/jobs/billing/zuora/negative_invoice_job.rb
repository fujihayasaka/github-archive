# typed: true
# frozen_string_literal: true

class Billing::Zuora::NegativeInvoiceJob < ApplicationJob
  queue_as :billing

  retry_on GitHub::Restraint::UnableToLock,
    attempts: 3,
    wait: :polynomially_longer

  # account_is_billing_enabled is temporary to support metrics gathering
  # see https://github.com/github/sponsors/issues/4075#issuecomment-1252561173
  def perform(invoice_id:, account_is_billing_enabled: nil)
    @invoice_id = invoice_id
    @account_is_billing_enabled = account_is_billing_enabled

    record_metrics
    if zuora_invoice.balance.negative?
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.billing.zuora.invoice.id" => invoice_id,
        "gh.billing.zuora.invoice.number" => zuora_invoice.number,
        "gh.billing.zuora.invoice.amount" => zuora_invoice.amount,
        "gh.billing.zuora.invoice.balance" => zuora_invoice.balance
      )
      zero_out_invoice
    end
  end

  private

  def record_metrics
    # account_is_billing_enabled is temporary to support metrics gathering
    # see https://github.com/github/sponsors/issues/4075#issuecomment-1252561173
    if @account_is_billing_enabled && zuora_invoice.balance.negative?
      GitHub.dogstats.count("zuora.invoices.temp.billing_enabled_neg_inv_job_neg_inv_balance_in_cents",
        (zuora_invoice.balance * 100).abs
      )
    end

    Billing::Zuora::Invoice.record_metrics(
      balance_in_cents: zuora_invoice.balance * 100,
      calling_class: "negative_invoice_job",
    )
  end

  def zero_out_invoice
    Billing::Zuora::ZeroOutInvoice.run(invoice: zuora_invoice)
  end

  def zuora_invoice
    @zuora_invoice ||= ::Billing::Zuora::Invoice.new(@invoice_id)
  end
end
