# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteIssue < Platform::Mutations::Base
      description "Deletes an Issue object."

      minimum_accepted_scopes ["public_repo"]

      argument :issue_id, ID, "The ID of the issue to delete.", required: true, loads: Objects::Issue

      field :repository, Objects::Repository, "The repository the issue belonged to", null: true
      field :issue, Objects::Issue, "The issue that was removed.", null: true, visibility: :internal
      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue:, **inputs)
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(:delete_issue, resource: issue, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(issue:)
        viewer = context[:viewer]

        issue.async_repository.then do |repository|
          context[:permission].authorize_content(:issue, :update, repo: repository)

          if !repository.has_issues?
            raise Errors::Unprocessable::IssuesDisabled.new
          end

          if !issue.deleteable_by?(viewer)
            raise Errors::Forbidden.new("Viewer not authorized to delete")
          end

          o = IssueOrchestration.delete_issue(issue: issue, actor: viewer)
          begin
            # we don't check for orchestration errors before executing because we rely on silently failing if the
            # issue is already being deleted in an orchestration
            o.execute
          rescue ActiveRecord::RecordNotDestroyed
            raise Errors::Unprocessable.new("The issue cannot be deleted at this time")
          else
            {
              repository: issue.repository,
              issue: issue,
              errors: {},
            }
          end
        end
      end
    end
  end
end
