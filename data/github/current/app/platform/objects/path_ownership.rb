# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PathOwnership < Platform::Objects::Base
      visibility :internal
      description "Represents the code ownership for a file path"
      minimum_accepted_scopes ["repo"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true` as this is only accessible to internal users
      def self.async_api_can_access?(permission, object)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true` as this is only accessible to internal users
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :path_owners, [Objects::PathOwner], null: false, description: "The list of owners for this file path.", visibility: :internal

      field :rule_line_number, Integer, null: true, description: "The rule line number for this file path.", visibility: :internal

      field :rule_url, Scalars::URI, null: true, description: "The URL to the rule for this file path.", visibility: :internal

      field :is_owned_by_viewer, Boolean, null: false, description: "Whether the viewer is a path owner for this file path.", visibility: :internal

      def is_owned_by_viewer
        viewer = @context[:viewer]
        return false unless viewer
        @object.owned_by_viewer?(viewer)
      end
    end
  end
end
