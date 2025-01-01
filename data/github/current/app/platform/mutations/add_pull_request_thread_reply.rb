# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPullRequestThreadReply < Platform::Mutations::Base
      extend T::Sig

      description "Adds a reply to an existing Pull Request Thread."

      minimum_accepted_scopes ["public_repo"]

      visibility :internal

      argument :pull_request_thread_id, ID, "The Node ID of the thread to which this reply is being written.", required: true, loads: Objects::PullRequestThread, as: :thread
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

      # @param [Platform::Models::PullRequestThread] thread
      # @param [String] body
      # @param [Boolean] submit_review
      def resolve(thread:, body:, submit_review: false, **inputs)
        user = T.let(context[:viewer], User)
        review_thread = T.let(thread.review_thread, PullRequestReviewThread)

        Promise.all([
          review_thread.async_pull_request,
          review_thread.async_repository,
        ]).then do |pull_request, repository|
          pull_request = T.let(pull_request, PullRequest)
          repository = T.let(repository, Repository)
          review = pull_request.pending_review_for(user:)

          result = PullRequests::ReviewComments::Reply.create(
            repository:, pull_request:, review:, user:, body:, submit_review:,
            thread: review_thread
          )

          case result
          when PullRequests::ReviewComments::Reply::Success
            comment = result.comment
          when PullRequests::ReviewComments::Reply::Error
            comment = result
          end

          if comment.errors.empty?
            { comment: comment, errors: [] }
          else
            { comment: nil, errors: Platform::UserErrors.mutation_errors_for_model(comment) }
          end
        end
      end
    end
  end
end
