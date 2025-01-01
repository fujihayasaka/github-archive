# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class ResponsiveMenuComponent < ApplicationComponent

      sig { params(listing: Marketplace::Listing, selected_tab: T.nilable(Symbol)).void }
      def initialize(listing:, selected_tab:)
        @listing = listing
        @selected_tab = selected_tab
      end

      private

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { returns(T.nilable(Symbol)) }
      attr_reader :selected_tab

      sig { returns(T::Boolean) }
      def render?
        listing.present? && GitHub.marketplace_enabled? && logged_in?
      end
    end
  end
end
