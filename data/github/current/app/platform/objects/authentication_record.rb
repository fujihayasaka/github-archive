# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AuthenticationRecord < Platform::Objects::Base
      description "Represents a successful password authentication."

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
        permission.belongs_to_viewer(object) || Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      minimum_accepted_scopes %w(site_admin)

      global_id_field :id, description: "The Node ID of the AuthenticationRecord object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :user, User, method: :async_user, description: "The account being logged in to.", null: false

      field :country_code, String, "The two letter country abbreviation.", null: true

      field :octolytics_id, String, "The octolytics/device ID performing the login.", null: true

      field :client, Enums::AuthenticationClient, "The type of login attempt (e.g. :web, :git, :api, etc.).", null: true

      def client
        @object.client && @object.client.downcase
      end

      created_at_field(description: "When the token was created.")

      field :user_agent, String, "The user agent that performed the login.", null: true

      field :ip, String, "IP address.", null: false, method: :ip_address

      field :unexpected_login_reason, Enums::AuthenticationFlaggedReason, "(Optional) the reason the login was flagged as unexpected.", null: true

      def unexpected_login_reason
        @object.flagged_reason && @object.flagged_reason.downcase
      end
    end
  end
end
