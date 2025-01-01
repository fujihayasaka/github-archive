# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePullRequestReview < Platform::Mutations::Base
      description "Updates the body of a pull request review."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_review_id, ID, "The Node ID of the pull request review to modify.", required: true, loads: Objects::PullRequestReview, as: :review
      argument :body, String, "The contents of the pull request review body.", required: true

      field :pull_request_review, Objects::PullRequestReview, "The updated pull request review.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, review:, **inputs)
        review.async_pull_request.then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(:update_pull_request_comment, repo: repo, current_org: org, resource: review, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(review:, **inputs)
        check_database_resource_update_rate_limit!(resource: review, current_user: context[:viewer])

        if review.body.blank?
          raise Errors::Validation.new("Could not edit a review with a missing body.")
        end

        review.update_body(inputs[:body], context[:viewer])

        if review.valid?
          { pull_request_review: review }
        else
          raise Errors::Unprocessable.new(review.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
