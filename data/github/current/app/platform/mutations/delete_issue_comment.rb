# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteIssueComment < Platform::Mutations::Base
      description "Deletes an IssueComment object."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The ID of the comment to delete.", required: true, loads: Objects::IssueComment, as: :comment
      field :issue_comment, Objects::IssueComment, "The deleted issue comment", null: true, visibility: :internal

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        permission.async_repo_and_org_owner(comment).then do |repo, org|
          permission.access_allowed?(:delete_issue_comment, repo: repo, resource: comment, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(comment:, **inputs)
        issue = comment.issue

        context[:permission].authorize_content(:issue_comment, :delete, issue: issue, repo: issue.repository)

        if !context[:actor].can_have_granular_permissions? && !comment.async_viewer_can_delete?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to delete the comment '#{comment.global_relay_id}'."
          raise Errors::Forbidden.new(message)
        end

        comment.destroy

        {
          issue_comment: comment
        }
      end
    end
  end
end
