# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    class InvoicedBilling::InvoiceList::InvoiceComponent < ApplicationComponent
      sig { params(invoice: Stripe::Invoice).void }
      def initialize(invoice:)
        stripe_invoice = invoice
        @invoice = T.let(Billing::Stripe::Invoice.from_invoice(stripe_invoice), Billing::Stripe::Invoice)
      end

      private

      sig { returns(Billing::Stripe::Invoice) }
      attr_reader :invoice

      sig { returns(String) }
      def formatted_invoice_amount
        invoice.amount_due.format(
          no_cents_if_whole: true,
          with_currency: true,
        )
      end

      sig { returns(Symbol) }
      def label_scheme
        invoice.status == "paid" ? :success : :default
      end

      sig { returns(String) }
      def label_text
        invoice.status == "paid" ? "Paid" : "Open"
      end
    end
  end
end
