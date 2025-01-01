# typed: strict
# frozen_string_literal: true

module Platform
  module Resolvers
    class PendingSubscribableChanges < Resolvers::Base
      extend T::Sig

      argument :listing_slug, String, "The slug of the Sponsors or Marketplace listing we want changes for.",
        required: false

      type Connections::PendingSubscribableChange, null: false
      sig { params(listing_slug: T.nilable(String)).returns(Promise[T::Array[Billing::PendingSubscriptionItemChange]]) }
      def resolve(listing_slug: nil)
        changes = object.pending_subscription_item_changes.non_free_trial
        return Promise.resolve(changes.to_a) if listing_slug.blank?

        if ::SponsorsListing.sponsors_slug?(listing_slug)
          Platform::Loaders::ActiveRecord.load(::SponsorsListing, listing_slug, column: :slug).then do |sponsors_listing|
            changes.for_sponsors_listing(sponsors_listing).to_a
          end
        else # Marketplace listing
          Promise.resolve(changes.for_marketplace_listing_slug(listing_slug).to_a)
        end
      end
    end
  end
end
