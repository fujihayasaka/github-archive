# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class AdminSidebarComponent < ApplicationComponent
      extend T::Sig

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
    end
  end
end
