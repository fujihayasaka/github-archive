# typed: true
# frozen_string_literal: true

module Sponsors
  module Orgs
    class LowCreditBalanceComponent < ApplicationComponent
      CONTAINER_SIZES = %i(xl lg md sm).freeze
      DEFAULT_CONTAINER_SIZE = :lg

      # sponsor - a User or Organization
      # container_size - how large a Primer container (https://primer.style/css/objects/grid#containers) to render
      #                  the call-to-action in; defaults to :lg for a .container-lg
      def initialize(sponsor:, container_size: DEFAULT_CONTAINER_SIZE)
        @sponsor = sponsor
        @container_size = fetch_or_fallback(CONTAINER_SIZES, container_size, DEFAULT_CONTAINER_SIZE)
      end

      def new_invoice_url
        new_org_sponsoring_invoice_path(sponsor)
      end

      private

      attr_reader :sponsor, :container_size

      delegate :sponsors_customer, to: :sponsor

      def render?
        return false unless GitHub.sponsors_enabled?
        return false unless logged_in?
        return false unless sponsor&.sponsors_invoiced?
        return false unless current_user.potential_organization_sponsor_ids.include?(sponsor.id)
        return false unless sponsors_customer.low_sponsorship_credit_balance?


        # Only display the banner if the customer has succesfully paid an invoice before
        sponsors_customer.billing_transactions.successful.any?
      end

      def support_url
        SponsorsListing.support_url(subject: SponsorsPrimerMailer::INVOICE_BALANCE_SUPPORT_SUBJECT)
      end

      def low_balance_threshold
        Billing::Money.new(Customer::SponsorsDependency::MINIMUM_INVOICE_AMOUNT_IN_CENTS, "USD")
      end

      # Private: Indicates if the sponsor is able to create self-serve invoices.
      #          This requires them to have a Stripe account set up, not just to be invoiced.
      #
      # Returns a Boolean.
      def self_serve_invoices_enabled?
        sponsor.stripe_customer_id.present?
      end
    end
  end
end
