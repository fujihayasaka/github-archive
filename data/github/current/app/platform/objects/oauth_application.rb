# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # Intentionally not globally-identifiable for now until we can figure out
    # the security implications around loading arbitrary oauth applications.
    class OauthApplication < Platform::Objects::Base
      description "Represents an OAuth application"

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
        return false unless permission.viewer

        !object.hide_from_user?(permission.viewer)
      end

      visibility :internal

      implements Interfaces::MarketplaceIntegratable

      minimum_accepted_scopes ["repo"]

      database_id_field

      field :name, String, "The name of the application.", null: true

      field :url, Scalars::URI, "The URL to the application's homepage.", null: true

      field :logo_url, Scalars::URI, description: "A URL pointing to the application's logo.", null: false do
        argument :size, Integer, "The size of the resulting image.", required: false
      end

      def logo_url(**arguments)
        @object.async_preferred_avatar_url(size: arguments[:size])
      end

      field :key, String, "The key of the application.", null: false

      # Named this way so the field name has the capitalized H, i.e. isGitHubOwned
      field :is_git_hub_owned, Boolean, "Does the application belongs to GitHub?", null: false, method: :github_owned?

      field :user, User, method: :async_user, description: "The user associated with this application.", null: true
    end
  end
end
