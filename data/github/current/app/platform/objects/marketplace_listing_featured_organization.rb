# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceListingFeaturedOrganization < Platform::Objects::Base
      model_name "Marketplace::ListingFeaturedOrganization"
      description "A featured customer of this Marketplace Listing."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_listing.then do |listing|
          permission.typed_can_access?("MarketplaceListing", listing)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::ListingFeaturedCustomer object
      def self.async_viewer_can_see?(permission, object)
        return true if object.approved?

        return true if permission.viewer.can_admin_marketplace_listings?

        object.async_listing.then do |listing|
          listing.async_listable.then do
            listing.allowed_to_edit?(permission.viewer)
          end
        end
      end

      visibility :internal, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["repo"]
      global_id_field :id, description: "The Node ID of the MarketplaceListingFeaturedOrganization object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      database_id_field(visibility: :internal)

      field :organization, Objects::Organization, "The featured organization.", null: false, method: :async_organization
      field :listing, Objects::MarketplaceListing, "The Marketplace Listing the organization is featured on.", null: false, method: :async_listing
      field :approved, Boolean, "Whether or not this featured organization is approved to be displayed on the listing", null: false, visibility: :internal
    end
  end
end
