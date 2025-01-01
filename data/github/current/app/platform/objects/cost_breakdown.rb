# typed: true
# frozen_string_literal: true
module Platform
  module Objects
    class CostBreakdown < Platform::Objects::Base
      description "Per-field breakdown of total query cost"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _breakdown)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal
      scopeless_tokens_as_minimum
      field :field_name, String, "The field that added to query cost", null: false
      field :cost, Integer, "The amount this field contributed to query cost", null: false
      field :line, Integer, "The line number where this field was written", null: false
      field :column, Integer, "The column number where this field was written", null: false
    end
  end
end
