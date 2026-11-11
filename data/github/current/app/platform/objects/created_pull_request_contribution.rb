# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CreatedPullRequestContribution < Objects::Base

      scopeless_tokens_as_minimum

      implements Interfaces::Contribution

      description "Represents the contribution a user made on GitHub by opening a pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, contrib)
        permission.typed_can_access?("PullRequest", contrib.pull_request)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull_request)
      end

      field :pull_request, PullRequest, null: false,
        description: "The pull request that was opened."
    end
  end
end
