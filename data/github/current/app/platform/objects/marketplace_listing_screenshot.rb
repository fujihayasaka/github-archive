# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceListingScreenshot < Platform::Objects::Base
      model_name "::Marketplace::ListingScreenshot"
      description "A screenshot for a listing in the GitHub Marketplace."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::ListingScreenshot object
      def self.async_viewer_can_see?(permission, object)
        object.async_listing.then do |listing|
          permission.typed_can_see?("MarketplaceListing", listing)
        end
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the MarketplaceListingScreenshot object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :caption, String, "A description of the image.", null: true

      field :alt_text, String, description: "An alternative description of the screenshot that may be used if the image cannot be viewed.", null: false

      def alt_text
        if @object.caption.present?
          # Screen readers will read the caption so no need to repeat it
          ""
        else
          @object.async_listing.then do |listing|
            "#{listing.name} screenshot"
          end
        end
      end

      field :content_type, String, "The content type of the image.", null: false

      field :url, Scalars::URI, description: "The URL to the image.", null: false

      def url
        @object.async_listing.then do
          @object.storage_external_url(@context[:viewer])
        end
      end
    end
  end
end
