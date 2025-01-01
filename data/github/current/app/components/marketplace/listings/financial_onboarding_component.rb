# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class FinancialOnboardingComponent < ApplicationComponent
      extend T::Sig

      include MarketplaceHelper

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { returns(T.nilable(String)) }
      attr_reader :plan_id

      sig do
        params(
          listing: Marketplace::Listing,
          plan_id: T.nilable(String),
        ).void
      end
      def initialize(listing:, plan_id: nil)
        @listing = listing
        @plan_id = plan_id
      end

      sig { returns(T::Boolean) }
      def render?
        return false if is_draft

        is_unverified || is_verification_pending_from_unverified || is_verified_listing
      end

      sig { returns(T::Boolean) }
      def is_draft
        listing.draft?
      end

      sig { returns(T::Boolean) }
      def is_unverified
        listing.unverified?
      end

      sig { returns(T::Boolean) }
      def is_verification_pending_from_unverified
        listing.verification_pending_from_unverified?
      end

      sig { returns(T::Boolean) }
      def is_verified_listing
        listing.verified_listing?
      end

      sig { returns(T::Boolean) }
      def can_initiate_financial_onboarding
        listing.initiate_financial_onboarding?
      end
    end
  end
end
