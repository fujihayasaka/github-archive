# typed: true
# frozen_string_literal: true

module Marketplace::DelistDependency
  include Marketplace::NotifySpammyList
  def delist_marketplace_apps
    # delisting the app for the spammy users
    integration_ids = T.unsafe(self).integrations.pluck(:id)
    oauth_app_ids = T.unsafe(self).oauth_applications.pluck(:id)

    listings = Marketplace::Listing.for_integratables(oauth_app_ids, integration_ids)

    # delist the app if it is publicly listed
    listings.publicly_listed.map do |listing|
      listing.delist!
      # create a issue for marketplace-ops to send email notification to the subscribers.
      initiate_spammy_listing_notifications(listing) if listing.listing_plans.paid
    end
  end
end
