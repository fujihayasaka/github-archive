# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceListingPlanBullet < Platform::Objects::Base
      model_name "::Marketplace::ListingPlanBullet"
      description "A bullet point describing a payment plan for a listing in the GitHub Marketplace."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::ListingPlanBullet object
      def self.async_viewer_can_see?(permission, object)
        object.async_listing_plan.then do |listing_plan|
          permission.typed_can_see?("MarketplaceListingPlan", listing_plan)
        end
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the MarketplaceListingPlanBullet object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field

      field :value, String, "The contents of the bullet point.", null: false
    end
  end
end
