# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class InstallationRequirementComponent < ApplicationComponent

      include MarketplaceHelper

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { returns(Integer) }
      attr_reader :installation_count

      sig do
        params(
          listing: Marketplace::Listing,
          installation_count: Integer,
        ).void
      end
      def initialize(listing:, installation_count:)
        @listing = listing
        @installation_count = installation_count
      end

      sig { returns(T::Boolean) }
      def has_installation_requirements_met
        listing.has_installation_requirements_met?
      end

      sig { returns(Integer) }
      def required_installations_for_verification
        listing.required_installations_for_verification
      end
    end
  end
end
