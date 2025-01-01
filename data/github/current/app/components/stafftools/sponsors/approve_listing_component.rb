# typed: strict
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class ApproveListingComponent < ApplicationComponent
      extend T::Sig

      sig { params(listing: SponsorsListing).void }
      def initialize(listing:)
        @listing = listing
      end

      private

      sig { returns(SponsorsListing) }
      attr_reader :listing

      sig { returns(T::Boolean) }
      def render?
        return false unless listing.present?

        listing.approvable_by?(current_user)
      end
    end
  end
end
