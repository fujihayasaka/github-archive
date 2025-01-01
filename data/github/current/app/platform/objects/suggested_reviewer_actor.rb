# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SuggestedReviewerActor < Platform::Objects::Base
      description "A suggestion to review a pull request based on an actor's commit history, review comments, and integrations."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.typed_can_access?("PullRequest", object.pull)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull)
      end

      scopeless_tokens_as_minimum

      field :is_author, Boolean, method: :author?, description: "Is this suggestion based on past commits?", null: false

      field :is_commenter, Boolean, method: :commenter?, description: "Is this suggestion based on past review comments?", null: false

      field :reviewer, Interfaces::Actor, method: :user, description: "Identifies the actor suggested to review the pull request.", null: false
    end
  end
end
