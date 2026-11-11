# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserAssetUrl < Platform::Objects::Base
      description "An internal object for getting a user asset's URL"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :id, Integer, "Database ID", null: false
      field :url, Scalars::URI, "The asset's URL to render it.", null: false
    end
  end
end
