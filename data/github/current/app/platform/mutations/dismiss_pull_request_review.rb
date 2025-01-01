# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DismissPullRequestReview < Platform::Mutations::Base
      description "Dismisses an approved or rejected pull request review."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_review_id, ID, "The Node ID of the pull request review to modify.", required: true, loads: Objects::PullRequestReview, as: :review
      argument :message, String, "The contents of the pull request review dismissal message.", required: true

      field :pull_request_review, Objects::PullRequestReview, "The dismissed pull request review.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, review:, **inputs)
        permission.async_repo_and_org_owner(review).then do |repo, org|
          permission.access_allowed?(:dismiss_pull_request_review, repo: repo, current_org: org, resource: review, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(review:, **inputs)
        if review.pull_request.base_branch_rule_evaluator&.restricted_dismissed_reviews? &&
          !review.pull_request.base_branch_rule_evaluator.review_dismissable_by?(context[:viewer])

          raise Errors::Unprocessable.new("Branch protections do not permit dismissing this review.")
        end

        unless review.can_trigger?(:dismiss)
          state = PullRequestReview.state_name(review.state)
          raise Errors::Validation.new("Can not dismiss a #{state} pull request review")
        end

        if inputs[:message].blank?
          raise Errors::Validation.new("A message is required to dismiss a pull request review.")
        end

        review.trigger(:dismiss, actor: context[:viewer], message: inputs[:message])

        if review.persisted?
          { pull_request_review: review }
        else
          raise Errors::Unprocessable.new("Could not dismiss pull request review.")
        end
      end
    end
  end
end
