# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CheckAnnotationPosition < Platform::Objects::Base
      description "A character position in a check annotation."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(_permission, _object)
        # No special API permissions
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # true because it's a field type off of a check annotation
      # and has no additional permissions
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :line, Integer, "Line number (1 indexed).", null: false
      field :column, Integer, "Column number (1 indexed).", null: true
    end
  end
end
