# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class DeleteListingComponent < ApplicationComponent
      # listing - a SponsorsListing
      def initialize(listing:)
        @listing = listing
      end

      private

      attr_reader :listing

      delegate :sponsorable_login, to: :listing

      def render?
        listing.present? && GitHub.sponsors_enabled? && logged_in?
      end

      memoize def human_reason_delete_is_not_allowed
        unless listing.deletable?
          listing.errors.full_messages.to_sentence
        end
      end

      def has_potentially_received_funds?
        listing.sponsorships.exists?
      end
    end
  end
end
