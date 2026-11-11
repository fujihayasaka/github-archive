# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorsListingFeaturedItem < Platform::Objects::Base
      description "A record that is promoted on a GitHub Sponsors profile."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, sponsors_listing_featured_item)
        sponsors_listing_featured_item.async_sponsors_listing.then do |sponsors_listing|
          sponsors_listing.async_sponsorable.then do |sponsorable|
            org = sponsorable.organization? ? sponsorable : nil
            permission.access_allowed?(:read_sponsors_listing,
              resource: sponsorable,
              sponsors_listing: sponsors_listing,
              current_org: org,
              current_repo: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false,
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a SponsorsListing object
      def self.async_viewer_can_see?(permission, sponsors_listing_featured_item)
        sponsors_listing_featured_item.async_sponsors_listing.then do |sponsors_listing|
          # Public data available to even anonymous viewers on the web when the Sponsors listing is published
          # (state=approved):
          next true if sponsors_listing.approved?

          viewer = permission.viewer
          next false unless viewer

          sponsors_listing.async_adminable_by?(viewer)
        end
      end

      scopeless_tokens_as_minimum
      minimum_accepted_scopes ["read:user", "read:org", "public_repo"]

      created_at_field
      updated_at_field

      implements_node(
        templates: [
          [:slfr, :repository_id, :sponsors_listing_featured_item_id],
          [:slfu, :user_id, :sponsors_listing_featured_item_id],
        ],
        as: "SLFI",
        ready_date: "1970-01-01",
      ) do |sponsors_listing_featured_item|
        if sponsors_listing_featured_item.featureable_type_User?
          {
            prefix: :slfu,
            user_id: sponsors_listing_featured_item.featureable_id,
            sponsors_listing_featured_item_id: sponsors_listing_featured_item.id
          }
        else
          {
            prefix: :slfr,
            repository_id: sponsors_listing_featured_item.featureable_id,
            sponsors_listing_featured_item_id: sponsors_listing_featured_item.id
          }
        end
      end

      field :featureable, Unions::SponsorsListingFeatureableItem, null: false, method: :async_featureable,
        description: "The record that is featured on the GitHub Sponsors profile."

      field :description, String, "Will either be a description from the sponsorable maintainer about why they " \
        "featured this item, or the item's description itself, such as a user's bio from their GitHub profile page.",
        null: true, method: :async_description

      field :position, Integer, "The position of this featured item on the GitHub Sponsors profile with a lower " \
        "position indicating higher precedence. Starts at 1.", null: false

      field :sponsors_listing, Objects::SponsorsListing, null: false, method: :async_sponsors_listing,
        description: "The GitHub Sponsors profile that features this record."
    end
  end
end
