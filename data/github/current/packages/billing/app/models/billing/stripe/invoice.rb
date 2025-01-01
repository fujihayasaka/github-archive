# typed: strict
# frozen_string_literal: true

module Billing
  module Stripe
    class Invoice
      extend T::Sig

      SERVICE_FEE_DESCRIPTION_REGEX = /\bservice fee\b/i
      private_constant :SERVICE_FEE_DESCRIPTION_REGEX

      # Public: Hydrate a Billing::Stripe::Invoice with data from Stripe.
      sig { params(invoice: ::Stripe::Invoice).returns(Invoice) }
      def self.from_invoice(invoice)
        new(invoice: invoice)
      end

      sig { params(invoice: ::Stripe::Invoice).void }
      def initialize(invoice:)
        @invoice = invoice
      end

      sig { returns String }
      def id
        @invoice.id
      end

      sig { returns String }
      def number
        @invoice.number
      end

      sig { returns String }
      def hosted_invoice_url
        @invoice.hosted_invoice_url
      end

      sig { returns String }
      def customer_id
        @invoice.customer
      end

      sig { returns String }
      def status
        @invoice.status
      end

      sig { returns String }
      def currency
        @invoice.currency
      end

      sig { returns Billing::Money }
      def total
        Billing::Money.new(@invoice.total, currency)
      end

      sig { returns T::Boolean }
      def paid?
        @invoice.paid
      end

      sig { returns Billing::Money }
      def amount_due
        Billing::Money.new(@invoice.amount_due, currency)
      end

      sig { returns Billing::Money }
      def amount_paid
        Billing::Money.new(@invoice.amount_paid, currency)
      end

      sig { returns Billing::Money }
      def amount_remaining
        Billing::Money.new(@invoice.amount_remaining, currency)
      end

      sig { returns Billing::Money }
      def service_fee
        fee_line_items = @invoice.lines.data.select do |line_item|
          # description is supported since metadata can't be added in the Stripe UI; this allows
          # for manual invoice creation with custom service fee via the Stripe UI.
          line_item.metadata["service_fee"] == "true" || line_item.description =~ SERVICE_FEE_DESCRIPTION_REGEX
        end
        fee_amount_in_subunits = fee_line_items.sum(&:amount)
        Billing::Money.new(fee_amount_in_subunits, currency)
      end

      sig { returns ActiveSupport::TimeWithZone }
      def created_at
        Time.zone.at(@invoice["created"])
      end

      sig { returns T.nilable(Organization) }
      def receiving_org
        return unless @invoice.metadata.present?
        receiving_org_login = @invoice.metadata["receiving_org"]
        Organization.find_by(login: receiving_org_login) if receiving_org_login.present?
      end

      sig { returns T.nilable(String) }
      def purchase_order_number
        return unless @invoice.metadata.present?
        @invoice.metadata["purchase_order_number"]
      end

      sig { returns User }
      def creator
        return User.ghost unless @invoice.metadata.present?
        actor_login = @invoice.metadata["actor"]
        return User.ghost if actor_login.blank?
        User.find_by(login: actor_login) || User.ghost
      end

      # Public: Emit invoice event to Hydro
      #
      # action - corresponds to Hydro event action, e.g "PAY", "CREATE")
      sig { params(action: String).void }
      def instrument(action:)
        GlobalInstrumenter.instrument("sponsors.sponsors_invoiced_account_stripe_invoice", {
          action: action,
          invoice: self,
        })
      end
    end
  end
end
