# typed: true
# frozen_string_literal: true

module Marketplace::Listings
  class OnboardingPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    delegate :name, :slug, to: :listing, prefix: true

    attr_reader :listing

    def initialize(listing:, current_user: nil, user_session: nil)
      @listing = listing
    end

    def metrics_progress_payload
      {
        marketplace_listing_id: listing.id,
        marketplace_listing_status: listing.status,
        webhook_completed: listing.webhook_completed?,
        plans_and_pricing_completed: listing.plans_and_pricing_completed?,
        contact_info_completed: listing.contact_info_completed?,
        listing_description_completed: listing.listing_description_completed?,
        product_screenshots_completed: listing.product_screenshots_completed?,
        listing_details_completed: listing.listing_details_completed?,
        logo_and_feature_card_completed: listing.logo_and_feature_card_completed?,
        naming_and_links_completed: listing.naming_and_links_completed?,
      }
    end
  end
end
