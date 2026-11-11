# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceListingAdminInfo < Platform::Objects::Base
      description "Marketplace listing information only visible to site administrators."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.viewer.can_admin_marketplace_listings? || object.listing.adminable_by?(permission.viewer)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :state, String, description: "The listing's current state.", null: false

      def state
        @object.listing.status
      end

      field :state_color, String, description: "The background color used for state labels.", null: false

      def state_color
        if @object.listing.draft?
          "blue"
        elsif @object.listing.archived? || @object.listing.rejected?
          "red"
        elsif @object.listing.verified?
          "green"
        elsif @object.listing.unverified?
          "yellow"
        else
          # The rest of the states are different types of approval requested
          "purple"
        end
      end

      field :state_octicon, String, description: "The name of the octicon used for state labels.", null: false

      def state_octicon
        if @object.listing.draft?
          "pencil"
        elsif @object.listing.archived? || @object.listing.rejected?
          "circle-slash"
        elsif @object.listing.verified? || @object.listing.unverified?
          "check"
        else
          # The rest of the states are different types of approval requested
          "eye"
        end
      end

      field :oauth_application, Objects::OauthApplication, description: "The OAuth application this listing represents.", null: true

      def oauth_application
        if @object.listing.listable_is_oauth_application?
          Loaders::ActiveRecord.load(::OauthApplication, @object.listing.listable_id)
        end
      end
    end
  end
end
