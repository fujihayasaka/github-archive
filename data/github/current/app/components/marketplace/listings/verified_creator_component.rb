# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class VerifiedCreatorComponent < ApplicationComponent

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { params(listing: Marketplace::Listing).void }
      def initialize(listing:)
        @listing = listing
      end

      sig { returns(T::Boolean) }
      def render?
        return false unless user_or_global_feature_enabled?(:marketplace_updated_verified_creator)

        listing.copilot_app? && !listing.verified_owner?
      end
    end
  end
end
