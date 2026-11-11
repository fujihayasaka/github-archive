# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeletePullRequestReview < Platform::Mutations::Base
      description "Deletes a pull request review."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_review_id, ID, "The Node ID of the pull request review to delete.", required: true, loads: Objects::PullRequestReview, as: :review

      field :pull_request_review, Objects::PullRequestReview, "The deleted pull request review.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, review:, **inputs)
        permission.async_repo_and_org_owner(review).then do |repo, org|
          permission.access_allowed?(:delete_pull_request_review, repo: repo, current_org: org, resource: review, allow_integrations: true, allow_user_via_granular_actor: true, installation_required: false)
        end
      end

      def resolve(review:, **inputs)

        unless review.pending?
          raise Errors::Unprocessable.new("Can not delete a non-pending pull request review")
        end

        if review.destroy
          { pull_request_review: review }
        else
          raise Errors::Unprocessable.new("Could not destroy pull request review.")
        end
      end
    end
  end
end
