# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UnknownSignature < Platform::Objects::Base
      description "Represents an unknown signature on a Commit or Tag."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.typed_can_access?("Repository", object.repository)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::GitSignature
    end
  end
end
