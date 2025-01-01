# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceListingInsight < Platform::Objects::Base
      description "Sales metrics for a Marketplace listing during a specified period."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::ListingInsight object
      def self.async_viewer_can_see?(permission, object)
        object.async_listing.then do |listing|
          listing.async_listable.then do
            listing.owner_or_admin?(permission.viewer)
          end
        end
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      field :recorded_on, Scalars::Date, "The date on which insight recording started", null: false

      field :page_views, Integer, "The number of page views in the current period", method: :pageviews, null: false
      field :visitors, Integer, "The number of unique visitors", null: false
      field :landing_uniques, Integer, "The number of unique visitors to the listing's landing page", null: false
      field :checkout_uniques, Integer, "The number of unique visitors to the listing's checkout pages", null: false
      field :new_purchases, Integer, "The number of new subscriptions purchased", null: false
      field :new_seats, Integer, "The number of seats in new subscriptions", null: false
      field :new_free_subscriptions, Integer, "The number of new subscriptions to free plans", null: false
      field :new_paid_subscriptions, Integer, "The number of new subscriptions to paid plans", null: false
      field :new_free_trial_subscriptions, Integer, "The number of new subscriptions to paid plans with free trials", null: false
      field :upgrades, Integer, "The number of subscriptions upgraded to a higher value plan", null: false
      field :upgraded_seats, Integer, "The number of seats in upgraded subscriptions", null: false
      field :downgrades, Integer, "The number of subscriptions downgraded to a lower value plan", null: false
      field :downgraded_seats, Integer, "The number of seats in downgraded subscriptions", null: false
      field :cancellations, Integer, "The number of subscriptions cancelled", null: false
      field :cancelled_seats, Integer, "The number of seats in cancelled subscriptions", null: false
      field :installs, Integer, "The number of times a user installed this listing's application by granting permissions", null: false
      field :mrr_gained, Integer, "The amount in cents of monthly recurring revenue added in new purchases and upgrades", null: false
      field :mrr_lost, Integer, "The amount in cents of monthly recurring revenue lost in cancellations and downgrades", null: false
      field :mrr_recurring, Integer, "The amount in cents of monthly recurring revenue from ongoing subscriptions", null: false
      field :free_trial_conversions, Integer, "The number of free trials that ended with a subscription to a paid plan", null: false
      field :free_trial_cancellations, Integer, "The number of free trials that ended without a subscription to a paid plan", null: false
    end
  end
end
