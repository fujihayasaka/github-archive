# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class InternalRepositoryAdvisory < Platform::Objects::Base
      description "A security advisory on a repository; a temporary stand-in until RepositoryAdvisory object becomes public"
      scopeless_tokens_as_minimum
      visibility :internal

      implements Interfaces::Advisory

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repository_advisory)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, repository_advisory)
        repository_advisory.async_readable_by?(permission.viewer)
      end

      def summary
        object.title
      end
    end
  end
end
