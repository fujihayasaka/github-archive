# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CreatedPullRequestReviewContribution < Objects::Base

      scopeless_tokens_as_minimum

      implements Interfaces::Contribution

      description "Represents the contribution a user made by leaving a review on a pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, contrib)
        permission.typed_can_access?("PullRequestReview", contrib.pull_request_review)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, contrib)
        permission.typed_can_see?("PullRequestReview", contrib.pull_request_review)
      end

      field :repository, Repository, null: false,
        description: "The repository containing the pull request that the user reviewed."

      field :pull_request_review, Objects::PullRequestReview, null: false,
        description: "The review the user left on the pull request."

      field :pull_request, PullRequest, null: false,
        description: "The pull request the user reviewed."
    end
  end
end
