# typed: strict
# frozen_string_literal: true

class Billing::Zuora::ZeroOutInvoice
  sig { params(invoice: Billing::Zuora::Invoice).void }
  def initialize(invoice:)
    @invoice = invoice
    @restraint = T.let(GitHub::Restraint.new, GitHub::Restraint)
  end

  sig { params(invoice: Billing::Zuora::Invoice).void }
  def self.run(invoice:)
    new(invoice: invoice).run
  end

  sig { void }
  def run
    lock_invoice(invoice) do
      response = GitHub.zuorest_client.create_action(objects: invoice_item_adjustments, type: "InvoiceItemAdjustment")

      results = response.map { |r| GitHub::Billing::Result.from_zuora(r) }
      success = results.all?(&:success?)

      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "run",
        "gh.catalog_service" => "github/payment_processing",
        "gh.billing.zuora.invoice_item_adjustments" => invoice_item_adjustments.to_s,
        "gh.billing.zuora.response_results" => results.map(&:to_s).to_s
      )

      GitHub.dogstats.increment("zuora.invoices.zero_out", tags: ["success:#{success}", "class:zero_out_invoice"])
    end
  end

  private

  sig { returns(Billing::Zuora::Invoice) }
  attr_reader :invoice

  sig { returns(GitHub::Restraint) }
  attr_reader :restraint

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def invoice_item_adjustments
    adjustment_amount = Billing::Money.new(-invoice.balance * 100)
    Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(invoice: invoice, adjustment_amount: adjustment_amount)
  end

  sig { params(invoice: Billing::Zuora::Invoice, block: T.proc.params(arg0: T.untyped).void).void }
  def lock_invoice(invoice, &block)
    restraint.lock! invoice.lock_key, _n = 1, _ttl = 1.minute, &block
  end
end
