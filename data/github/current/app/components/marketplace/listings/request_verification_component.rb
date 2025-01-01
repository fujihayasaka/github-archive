# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class RequestVerificationComponent < ApplicationComponent
      extend T::Sig

      include MarketplaceHelper

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { returns(String) }
      attr_reader :display_login

      sig do
        params(
          listing: Marketplace::Listing,
          display_login: String,
        ).void
      end
      def initialize(listing:, display_login:)
        @listing = listing
        @display_login = display_login
      end

      sig { returns(T::Boolean) }
      def has_verified_owner
        listing.verified_owner?
      end

      sig { returns(T::Boolean) }
      def is_owner_verification_pending
        listing.owner_verification_pending?
      end

      sig { returns(String) }
      def request_verification_path
        if listing.owner.organization?
          settings_org_publisher_path(display_login)
        else
          Marketplace::APPLY_FOR_PUBLISHER_VERIFICATION_DOCS
        end
      end
    end
  end
end
