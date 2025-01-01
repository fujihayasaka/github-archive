# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPullRequestReviewThreadReply < Platform::Mutations::Base
      description "Adds a reply to an existing Pull Request Review Thread."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_review_id, ID, "The Node ID of the pending review to which the reply will belong.", required: false, loads: Objects::PullRequestReview, as: :review
      argument :pull_request_review_thread_id, ID, "The Node ID of the thread to which this reply is being written.", required: true, loads: Objects::PullRequestReviewThread, as: :thread
      argument :body, String, "The text of the reply.", required: true
      argument :submit_review, Boolean, "True to mark this review as submitted", required: false, default_value: false, visibility: :internal

      error_fields
      field :comment, Objects::PullRequestReviewComment, "The newly created reply.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, thread:, **inputs)
        thread.async_pull_request.then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(:create_pull_request_comment, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(thread:, review: nil, **inputs)
        author = context[:viewer]

        if review
          comment = thread.build_reply(pull_request_review: review, user: author, body: inputs[:body])
        else
          if thread.pull_request.pending_review_by?(author)
            review = thread.pull_request.pending_review_for(user: author)
            comment = thread.build_reply(pull_request_review: review, user: author, body: inputs[:body])
          else
            review = thread.pull_request.pending_review_for(user: author)
            comment = thread.build_reply(pull_request_review: review, user: author, body: inputs[:body])

            PullRequestReview.transaction do
              raise ActiveRecord::Rollback unless review.save && thread.save && comment.save  # rubocop:disable GitHub/UsePlatformErrors

              review.comment!
            end
          end
        end

        if comment.save
          review.comment! if inputs[:submit_review]

          { comment: comment.reload, errors: [] }
        else
          { comment: nil, errors: Platform::UserErrors.mutation_errors_for_model(comment) }
        end
      end
    end
  end
end
