# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryCustomPropertyValue < Platform::Objects::Base
      description "A value associated with a repository custom property."

      minimum_accepted_scopes ["public_repo", "read:org"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, value)
        permission.typed_can_access?("Repository", value.target)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, value)
        permission.typed_can_see?("Repository", value.target)
      end

      include Platform::Helpers::CustomPropertyValueBase
    end
  end
end
