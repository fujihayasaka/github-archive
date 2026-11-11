# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class InvoiceOverviewComponent < ApplicationComponent
      attr_reader :invoice_balance_dollars,
        :invoice_due_on,
        :past_invoices_href,
        :pay_invoice_href,
        :show_invoice_href

      def initialize(invoice_balance_dollars:,
        invoice_due_on:,
        past_invoices_href:,
        pay_invoice_href:,
        show_invoice_href:)
        @invoice_balance_dollars = invoice_balance_dollars
        @invoice_due_on = invoice_due_on.respond_to?(:strftime) ? invoice_due_on : Date.parse(invoice_due_on)
        @past_invoices_href = past_invoices_href
        @pay_invoice_href = pay_invoice_href
        @show_invoice_href = show_invoice_href
      end

      def formatted_invoice_due_on
        invoice_due_on.strftime("%b %-d, %Y")
      end
    end
  end
end
