# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class NodeCountBreakdown < Platform::Objects::Base
      description "Per-type breakdown of possible nodes accessed"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, obj)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal
      scopeless_tokens_as_minimum

      field :type_name, String, "The type of node which may be accessed", null: false
      field :count, Integer, "The maximum number of nodes that this field may access", method: :cost, null: false
      field :field_name, String, "The field which may access these nodes", null: false
      field :line, Integer, "The line number where this field was written", null: false
      field :column, Integer, "The column number where this field was written", null: false
    end
  end
end
