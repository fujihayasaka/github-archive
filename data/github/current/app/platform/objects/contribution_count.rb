# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ContributionCount < Objects::Base
      visibility :under_development

      scopeless_tokens_as_minimum

      description "The amount a user has of a given type of contribution."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # No special API permissions
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :name, String, null: false, description: "The type of contribution.",
        method: :contribution_type
      field :count, Integer, null: false, description: "The count of contributions of this type."
      field :percentage, Integer, null: false,
        description: "The percentage of contributions of this type."
    end
  end
end
