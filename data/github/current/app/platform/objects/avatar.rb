
# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Avatar < Platform::Objects::Base
      description "A user's avatar"

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
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :under_development
      minimum_accepted_scopes ["read:user"]

      field :content_type, String, null: true, description: "The content type of the avatar"
      created_at_field(null: false, description: "The time the avatar was created")
      updated_at_field(null: false, description: "The time the avatar was updated")
      field :cropped_x, Integer, null: false, description: "The cropped width of the avatar"
      field :cropped_y, Integer, null: false, description: "The cropped height of the avatar"
      field :size, Integer, null: false, description: "The size of the avatar in bytes"
      field :url, Scalars::URI, null: false, description: "The URL for the avatar"
    end
  end
end
