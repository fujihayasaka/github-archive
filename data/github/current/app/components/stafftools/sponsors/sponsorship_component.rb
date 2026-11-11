# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class SponsorshipComponent < ApplicationComponent
      # sponsor - User or Organization
      # sponsorable - User or Organization
      # tier - a SponsorsTier
      # sponsors_listing - a SponsorsListing
      # is_paid - Boolean indicating whether the sponsorship payment has been received
      # sponsorship_id - Integer database ID of the Sponsorship record
      # is_premium_sponsor - Boolean indicating whether the sponsor is a Premium Sponsor
      # tier_selected_at - optional DateTime for when the tier was chosen for the sponsorship
      # odd_row - Boolean indicating whether this row is an odd one in the list/table of all sponsorships
      # line_item - optional Billing::BillingTransaction::LineItem for the sponsorship, with its
      #             `billing_transaction` relation preloaded
      # is_private - Boolean indicating if the Sponsorship is private, meaning the sponsor's identity is not public
      # via_bulk_sponsorship - Boolean indicating if the Sponsorship was made via the bulk sponsorship feature
      # via_patreon - Boolean indicating if the Sponsorship was paid for on Patreon instead of GitHub
      sig do
        params(
          sponsor: T.nilable(T.any(::User, ::Organization)),
          sponsorable: T.nilable(T.any(::User, ::Organization)),
          tier: SponsorsTier,
          sponsors_listing: SponsorsListing,
          is_paid: T::Boolean,
          sponsorship_id: Integer,
          is_private: T::Boolean,
          is_premium_sponsor: T::Boolean,
          tier_selected_at: T.nilable(T.any(DateTime, ActiveSupport::TimeWithZone)),
          odd_row: T::Boolean,
          line_item: T.nilable(::Billing::BillingTransaction::LineItem),
          via_bulk_sponsorship: T::Boolean,
          via_patreon: T::Boolean
        ).void
      end
      def initialize(sponsor:, sponsorable:, tier:, sponsors_listing:, is_paid:, sponsorship_id:, is_private:, is_premium_sponsor: false, tier_selected_at: nil, odd_row: false, line_item: nil, via_bulk_sponsorship: false, via_patreon: false)
        @sponsor = sponsor
        @sponsorable = sponsorable
        @tier = tier
        @sponsors_listing = sponsors_listing
        @odd_row = odd_row
        @is_paid = is_paid
        @line_item = line_item
        @is_premium_sponsor = is_premium_sponsor
        @sponsorship_id = sponsorship_id
        @is_private = is_private
        @tier_selected_at = tier_selected_at
        @via_bulk_sponsorship = via_bulk_sponsorship
        @via_patreon = via_patreon
      end

      private

      sig { returns SponsorsTier }
      attr_reader :tier

      sig { returns SponsorsListing }
      attr_reader :sponsors_listing

      sig { returns T.nilable(::Billing::BillingTransaction::LineItem) }
      attr_reader :line_item

      sig { returns Integer }
      attr_reader :sponsorship_id

      sig { returns T.nilable(T.any(DateTime, ActiveSupport::TimeWithZone)) }
      attr_reader :tier_selected_at

      sig { returns T::Boolean }
      def render?
        return false unless GitHub.sponsors_enabled? && logged_in?
        return false unless @sponsor && @sponsorable && tier && sponsors_listing && sponsorship_id
        if line_item
          unless T.must(line_item).subscribable_id == tier.id && T.must(line_item).subscribable_SponsorsTier?
            return false
          end
        end
        tier.sponsors_listing_id == sponsors_listing.id
      end

      sig { returns T.any(::User, ::Organization) }
      memoize def sponsor
        @sponsor || ::User.ghost
      end

      sig { returns T.any(::User, ::Organization) }
      memoize def sponsorable
        @sponsorable || ::User.ghost
      end

      sig { returns T::Boolean }
      def odd_row?
        @odd_row
      end

      sig { returns T::Boolean }
      def via_bulk_sponsorship?
        @via_bulk_sponsorship
      end

      sig { returns T::Boolean }
      def private_sponsorship?
        @is_private
      end

      sig { returns T::Boolean }
      def premium_sponsor?
        @is_premium_sponsor
      end

      sig { returns T::Boolean }
      def paid?
        @is_paid
      end

      sig { returns T::Boolean }
      def patreon?
        @via_patreon
      end

      sig { returns T.nilable(::Billing::BillingTransaction) }
      memoize def billing_transaction
        line_item&.billing_transaction
      end
    end
  end
end
