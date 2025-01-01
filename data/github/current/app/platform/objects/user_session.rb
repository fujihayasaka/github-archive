# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserSession < Platform::Objects::Base
      description "A logged in browser session."

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

      minimum_accepted_scopes ["site_admin"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the UserSession object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :ip, String, "Most recent activity IP address.", null: false
      field :accessed_at, Scalars::DateTime, "The time of most recent activity.", null: false
      field :user_agent, String, "The user agent using the current session.", null: true
      field :location, Objects::Location, "The location information available for the user session.", null: true

      field :expire_time, Scalars::DateTime, "The date/time that this user session is expired", null: true
      def expire_time
        Loaders::ActiveRecordAssociation.load(@object, :user).then do
          @object.expire_time
        end
      end

      field :is_expired, Boolean, "Is the session expired?", null: false
      def is_expired
        Loaders::ActiveRecordAssociation.load(@object, :user).then do
          @object.expired?
        end
      end

      field :is_revoked, Boolean, "Is the session revoked?", null: false, method: :revoked?
    end
  end
end
