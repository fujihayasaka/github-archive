# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # Intentionally not globally-identifiable.
    class OauthAccess < Platform::Objects::Base
      description "Represents an OAuth application access"

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

      database_id_field
      created_at_field
      updated_at_field

      field :token_last_eight, String, "The last eight characters of this OauthAccess", null: false
      field :accessed_at, Scalars::DateTime, "The last time this authorization was used to perform an action", null: true
      field :scopes, String, method: :scopes_string, description: "The list of scopes this Credential is authorized for as a sorted, comma-separated String", null: false
      field :application, Objects::OauthApplication, method: :async_application, description: "The associated OAuth application.", null: true
      field :user, User, method: :async_user, description: "The user associated with this access.", null: true
    end
  end
end
