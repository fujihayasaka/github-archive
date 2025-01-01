# typed: strict
# frozen_string_literal: true

module Marketplace
  module ListingPlans
    class PaidPlanChecklistComponent < ApplicationComponent
      extend T::Sig

      include MarketplaceHelper

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { returns(String) }
      attr_reader :display_login

      sig { returns(Integer) }
      attr_reader :installation_count

      sig { returns(T.nilable(String)) }
      attr_reader :plan_id

      sig do
        params(
          listing: Marketplace::Listing,
          display_login: String,
          installation_count: Integer,
          plan_id: T.nilable(String),
        ).void
      end
      def initialize(listing:, display_login:, installation_count:, plan_id: nil)
        @listing = listing
        @display_login = display_login
        @installation_count = installation_count
        @plan_id = plan_id
      end

      sig { returns(T::Boolean) }
      def is_draft
        listing.draft?
      end
    end
  end
end
