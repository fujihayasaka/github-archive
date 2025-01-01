# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class PastInvoicesComponent < ApplicationComponent
      attr_reader :target, :invoices, :can_make_payment

      def initialize(target:, invoices:, invoice_path_builder:, can_make_payment: true)
        @target = target
        @invoices = invoices
        @invoice_path_builder = invoice_path_builder
        @can_make_payment = can_make_payment
      end

      def amount(invoice)
        Billing::Money.new(invoice.amount * 100).format
      end

      def payment_method_href(invoice)
        if target.business?
          invoice_payment_method_enterprise_path(target, invoice.number&.downcase)
        else
          invoice_payment_method_path(target, invoice.number&.downcase)
        end
      end

      def show_invoice_href(invoice)
        @invoice_path_builder.call(target, invoice.number&.downcase)
      end

      def octicon_icon(invoice)
        if invoice.paid?
          "check"
        elsif invoice.past_due?
          "alert"
        else
          "file"
        end
      end
    end
  end
end
