# typed: strict
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class MembershipActionsComponent < ApplicationComponent
      sig { params(sponsors_listing: SponsorsListing).void }
      def initialize(sponsors_listing:)
        @sponsors_listing = sponsors_listing
      end

      private

      sig { returns SponsorsListing }
      attr_reader :sponsors_listing

      sig { returns T::Boolean }
      def render?
        GitHub.sponsors_enabled?
      end

      sig { returns T::Boolean }
      memoize def unsupported_country?
        !(sponsors_listing.for_user? || sponsors_listing.eligible_for_stripe_connect?)
      end

      sig { returns T::Boolean }
      memoize def trade_restricted?
        sponsors_listing.sponsorable_has_any_trade_restrictions?
      end

      sig { returns T::Boolean }
      def show_undo_acceptance_button?
        sponsors_listing.can_revert_to_waitlisted?
      end

      sig { returns T::Boolean }
      def show_reactivate_button?
        sponsors_listing.can_reactivate?
      end

      sig { returns T::Boolean }
      def show_accept_button?
        return false if banned_or_ignored? || accepted_into_sponsors?
        sponsors_listing.can_accept? || (unsupported_country? && sponsors_listing.waitlisted?)
      end

      sig { returns T::Boolean }
      def show_undo_ban_button?
        sponsors_listing.banned?
      end

      sig { returns T::Boolean }
      def show_unignore_button?
        sponsors_listing.ignored?
      end

      sig { returns T::Boolean }
      memoize def accepted_into_sponsors?
        sponsors_listing.accepted_into_sponsors?
      end

      sig { returns T::Boolean }
      def banned_or_ignored?
        sponsors_listing.banned? || sponsors_listing.ignored?
      end

      sig { returns String }
      memoize def user_type
        sponsors_listing.for_user? ? "user" : "organization"
      end
    end
  end
end
