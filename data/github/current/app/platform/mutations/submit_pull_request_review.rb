# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SubmitPullRequestReview < Platform::Mutations::Base
      description "Submits a pending pull request review."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The Pull Request ID to submit any pending reviews.", required: false, loads: Objects::PullRequest, as: :pull
      argument :pull_request_review_id, ID, "The Pull Request Review ID to submit.", required: false, loads: Objects::PullRequestReview, as: :review
      argument :event, Enums::PullRequestReviewEvent, "The event to send to the Pull Request Review.", required: true
      argument :body, String, "The text field to set on the Pull Request Review.", required: false
      argument :head_sha, String, "The SHA of the head commit to submit the review against.", required: false, visibility: :internal

      field :pull_request_review, Objects::PullRequestReview, "The submitted pull request review.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        if inputs[:review]
          inputs[:review].async_pull_request.then do |pull|
            permission.async_repo_and_org_owner(pull).then do |repo, org|
              permission.access_allowed?(:submit_pull_request_review, repo: repo, current_org: org, resource: inputs[:review], allow_integrations: true, allow_user_via_granular_actor: true, installation_required: false)
            end
          end
        elsif inputs[:pull]
          permission.async_repo_and_org_owner(inputs[:pull]).then do |repo, org|
            permission.access_allowed?(:create_pull_request_comment, repo: repo, current_org: org, resource: inputs[:pull], allow_integrations: true, allow_user_via_granular_actor: true)
          end
        else
          false
        end
      end

      def resolve(**inputs)
        if inputs[:review]
          review = inputs[:review]
        elsif inputs[:pull]
          if inputs[:pull].pending_review_by?(context[:viewer])
            review = inputs[:pull].pending_review_for(user: context[:viewer])
          else
            raise Errors::Validation.new("No pending reviews exist on this pull request.")
          end
        else
          raise Errors::Validation.new("Review or Pull Request required.")
        end

        event = inputs[:event]
        body = inputs[:body]
        head_sha = inputs[:head_sha]

        review.body = body if body
        if head_sha
          review.head_sha = head_sha
          review.merge_base_sha = review.pull_request.find_best_merge_base_sha(head_sha: review.head_sha)
        end

        if review.can_trigger?(event) && review.trigger(event)
          { pull_request_review: review }
        else
          if review.halted?
            raise Errors::Unprocessable.new("Could not #{event} for pull request review. #{review.halted_because}")
          else
            raise Errors::Unprocessable.new("Could not #{event} pull request review.")
          end
        end
      end
    end
  end
end
