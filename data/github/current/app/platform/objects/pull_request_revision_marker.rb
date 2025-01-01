# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestRevisionMarker < Platform::Objects::Base
      description "Represents the latest point in the pull request timeline for which the viewer has seen the pull request's commits."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, marker)
        permission.typed_can_access?("PullRequest", marker.pull_request)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull_request)
      end

      scopeless_tokens_as_minimum

      field :pull_request, Objects::PullRequest, "The pull request to which the marker belongs.", null: false

      field :last_seen_commit, Objects::Commit, "The last commit the viewer has seen.", method: :async_last_seen_commit, null: false

      created_at_field
    end
  end
end
