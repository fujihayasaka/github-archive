# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class InvoicedSponsorshipsComponent < ApplicationComponent
      attr_reader :sponsor, :page

      PER_PAGE = 20

      def initialize(sponsor:, page: 1)
        @sponsor = sponsor
        @page = page
      end

      private

      def render?
        GitHub.sponsors_enabled? && sponsor.present? && logged_in?
      end

      memoize def sponsorships
        sponsorships = sponsor.active_sponsorships_as_sponsor_relation
          .invoiced
          .includes(invoiced_sponsorship_transfer: [:sponsorable, :sponsors_listing])
          .order(created_at: :desc)
        sponsorships.paginate(page: page, per_page: PER_PAGE)
      end

      def transfer_expires_on(transfer)
        transfer.sponsorship_expires_at.strftime("%m/%d/%Y")
      end

      def transfer_amount(transfer)
        transfer.amount_in_cents / 100.0
      end
    end
  end
end
