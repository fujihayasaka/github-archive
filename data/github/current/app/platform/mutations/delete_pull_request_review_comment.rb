# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeletePullRequestReviewComment < Platform::Mutations::Base
      description "Deletes a pull request review comment."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The ID of the comment to delete.", required: true, loads: Objects::PullRequestReviewComment, as: :comment

      field :pull_request_review, Objects::PullRequestReview, "The pull request review the deleted comment belonged to.", null: true
      field :pull_request_review_comment, Objects::PullRequestReviewComment, "The deleted pull request review comment.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        comment       = inputs[:comment]
        permission.async_repo_and_org_owner(comment).then do |repo, org|
          permission.access_allowed?(:delete_pull_request_comment, repo: repo, current_org: org, resource: comment, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(execution_errors:, **inputs)
        comment       = inputs[:comment]
        pull_request  = comment.pull_request

        context[:permission].authorize_content(:pull_request_comment, :delete, issue: pull_request.issue, repo: pull_request.repository)

        if !context[:actor].can_have_granular_permissions? && !comment.async_viewer_can_delete?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to delete the comment '#{comment.global_relay_id}'."
          raise Errors::Forbidden.new(message)
        end

        if comment.destroy
          {
            pull_request_review: comment.pull_request_review,
            pull_request_review_comment: comment,
            errors: [],
          }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(comment, execution_errors)

          {
            pull_request_review: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(comment),
          }
        end
      end
    end
  end
end
