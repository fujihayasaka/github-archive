# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Profile < Platform::Objects::Base
      description <<~DESCRIPTION
        Account profile record that includes metadata like timestamps.
        For internal use only.
        Please use public profile fields on User object for public use cases.
      DESCRIPTION

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

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      field :bio, String, "Profile bio.", null: true
      field :company, String, "Profile company.", null: true
      field :email, String, "Profile email.", null: true
      field :location, String, "Profile location.", null: true
      field :name, String, "Profile name.", null: true
      field :website_url, Scalars::URI, "Profile website URL.", null: true, method: :blog
      field :pronouns, String, "Profile pronouns.", null: true

      created_at_field
      updated_at_field
    end
  end
end
