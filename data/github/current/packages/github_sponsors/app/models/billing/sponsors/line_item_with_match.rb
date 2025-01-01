# typed: true
# frozen_string_literal: true

module Billing
  module Sponsors
    class LineItemWithMatch
      include GitHub::Memoizer

      delegate_missing_to :sponsors_line_item

      # Public: Initialize LineItemWithMatch
      #
      # sponsors_line_item - An instance of Billing::BillingTransaction::LineItem
      #
      # Returns LineItemWithMatch
      def initialize(sponsors_line_item)
        @sponsors_line_item = sponsors_line_item
        unless @sponsors_line_item.subscribable_SponsorsTier?
          raise "Line item does not look like it's for Sponsors"
        end
      end

      # Public: Calculate matching for current sponsors_line_item
      #
      # Returns Integer
      def match_amount_in_cents
        return 0 unless billable_entity.eligible_for_sponsorship_match?(sponsorable: sponsorable)
        ::Sponsors::CalculateMatch.for(listing, sponsorship_amount: amount_in_cents)
      end

      # Public: The sponsors_line_item amount in cents
      #
      # Returns Integer
      def amount_in_cents
        sponsors_line_item.amount_in_cents
      end

      # Public: The total amount of the sponsors_line_item, including the match
      #
      # Returns Integer
      def total_in_cents
        amount_in_cents + match_amount_in_cents
      end

      def sponsors_listing_id
        listing&.id
      end

      private

      attr_reader :sponsors_line_item

      delegate :listing, to: :sponsors_line_item

      memoize def billable_entity
        sponsors_line_item.billing_transaction.billable_entity
      end

      memoize def sponsorable
        listing.sponsorable
      end
    end
  end
end
