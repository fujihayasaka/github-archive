# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PendingMarketplaceChanges < Resolvers::Base
      argument :listing_slug, String, "The slug of the Marketplace or Sponsors listing we want changes for.",
        required: false

      type Connections::PendingMarketplaceChange, null: false

      def resolve(**arguments)
        changes = object.pending_subscription_item_changes.non_free_trial
        listing_slug = arguments[:listing_slug]
        return Promise.resolve(changes) if listing_slug.blank?

        if ::SponsorsListing.sponsors_slug?(listing_slug)
          Platform::Loaders::ActiveRecord.load(::SponsorsListing, listing_slug, column: :slug).then do |listing|
            changes.for_sponsors_listing(listing)
          end
        else # Marketplace
          changes.for_marketplace_listing_slug(listing_slug)
        end
      end
    end
  end
end
