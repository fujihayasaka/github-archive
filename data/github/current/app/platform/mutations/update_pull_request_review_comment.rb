# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePullRequestReviewComment < Platform::Mutations::Base
      description "Updates a pull request review comment."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_review_comment_id, ID, "The Node ID of the comment to modify.", required: true, loads: Objects::PullRequestReviewComment, as: :comment
      argument :body, String, "The text of the comment.", required: true

      field :pull_request_review_comment, Objects::PullRequestReviewComment, "The updated comment.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        review = comment.pull_request_review
        review.async_pull_request.then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(:update_pull_request_comment, repo: repo, current_org: org, resource: comment, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(comment:, **inputs)

        review = comment.pull_request_review

        unless review.is_a?(::PullRequestReview)
          raise Errors::NotFound.new("Could not resolve to a node with the global id of '#{inputs[:pull_request_review_id]}'.")
        end

        comment.update_body(inputs[:body], context[:viewer])

        if comment.valid?
          {
            pull_request_review_comment: comment,
          }
        else
          raise Errors::Unprocessable.new(comment.errors.full_messages.join(", "))
        end
      end
    end
  end
end
