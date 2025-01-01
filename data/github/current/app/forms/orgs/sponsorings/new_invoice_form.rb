# typed: strict
# frozen_string_literal: true

module Orgs
  module Sponsorings
    class NewInvoiceForm < ApplicationForm
      extend T::Sig
      include GitHub::Memoizer

      form do |new_invoice_form|
        T.bind(self, NewInvoiceForm)

        new_invoice_form.text_field(
          name: "stripe_invoice[amount_in_dollars]",
          type: :number,
          label: "Amount in US dollars",
          required: true,
          value: amount_in_dollars || "",
          min: Customer::SponsorsDependency::MINIMUM_INVOICE_AMOUNT_IN_CENTS / 100,
          step: 0.01,
          placeholder: amount_placeholder,
          caption: "This amount less the service fee (#{Sponsorship::PERCENT_SERVICE_FEE}%) will be added to your sponsorship balance.",
          style: "max-width: 350px;",
        )

        new_invoice_form.text_field(
          name: "stripe_invoice[purchase_order_number]",
          label: "Purchase order (PO) number (optional)",
          placeholder: "e.g., 21041258",
          value: purchase_order_number || "",
          caption: "If a purchase order is required, please contact support: #{GitHub.support_url}",
          style: "max-width: 350px;",
        )

        new_invoice_form.submit(
          name: :submit,
          label: "Create invoice",
          scheme: :primary,
          align_self: :end,
        )
      end

      sig do
        params(
          amount_in_dollars: T.nilable(String),
          purchase_order_number: T.nilable(String),
        ).void
      end
      def initialize(amount_in_dollars: nil, purchase_order_number: nil)
        @amount_in_dollars     = amount_in_dollars
        @purchase_order_number = purchase_order_number
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :amount_in_dollars, :purchase_order_number

      sig { returns(Billing::Money) }
      memoize def minimum_amount
        Billing::Money.new(Customer::SponsorsDependency::MINIMUM_INVOICE_AMOUNT_IN_CENTS)
      end

      sig { returns(String) }
      def amount_placeholder
        amount_whole = minimum_amount.format(no_cents_if_whole: true, symbol: false)
        amount_with_cents = minimum_amount.format(no_cents: false, symbol: false, delimiter: false)
        amount_formatted = minimum_amount.format(with_currency: true)

        "e.g., #{amount_whole} or #{amount_with_cents} for #{amount_formatted}"
      end
    end
  end
end
