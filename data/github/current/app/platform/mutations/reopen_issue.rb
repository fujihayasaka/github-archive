# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReopenIssue < Platform::Mutations::Base
      description "Reopen a issue."

      minimum_accepted_scopes ["public_repo"]

      argument :issue_id, ID, "ID of the issue to be opened.", required: true, loads: Objects::Issue

      field :issue, Objects::Issue, "The issue that was opened.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue:, **inputs)
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(:triage_issue, repo: repo, current_org: org, resource: issue, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(issue:)
        issue.async_repository.then do |repository|
          if !repository.has_issues?
            raise Errors::Unprocessable::IssuesDisabled.new
          end

          context[:permission].authorize_content(:issue, :update, repo: repository)

          check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

          if issue.open? || issue.open(context[:viewer], { state_reason: :reopened }) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
            { issue: issue }
          else
            raise Errors::Unprocessable.new("Could not reopen the issue.")
          end
        end
      end
    end
  end
end
