# typed: true
# frozen_string_literal: true

module Marketplace::DelistDependency
  include Marketplace::NotifySpammyList
  def delist_marketplace_apps
    # delisting the app for the spammy users
    listings = Marketplace::Listing.where(listable: [T.unsafe(self).integrations, T.unsafe(self).oauth_applications])
    # delist the app if it is publicly listed
    listings.publicly_listed.map do |listing|
      listing.delist!
      # create a issue for marketplace-ops to send email notification to the subscribers.
      initiate_spammy_listing_notifications(listing) if listing.listing_plans.paid
    end

  end
end
