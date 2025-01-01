# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PathOwner < Platform::Objects::Base
      visibility :internal
      description "Represents the owners defined in the CODEOWNERS file for a file path"
      minimum_accepted_scopes ["repo"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true` as this is only accessible to internal users
      def self.async_api_can_access?(permission, object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true` as this is only accessible to internal users
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :name, String, "The name of a User, Organization or Team", null: false

      def name
        user_org_or_team = @object.name
        user_org_or_team.is_a?(::Team) ? user_org_or_team.name : user_org_or_team.display_login
      end
    end
  end
end
