# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CloseIssue < Platform::Mutations::Base
      description "Close an issue."

      minimum_accepted_scopes ["public_repo"]

      argument :issue_id, ID, "ID of the issue to be closed.", required: true, loads: Objects::Issue

      argument :state_reason, Enums::IssueClosedStateReason, "The reason the issue is to be closed.", required: false

      field :issue, Objects::Issue, "The issue that was closed.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        issue = inputs[:issue]
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(:close_issue, repo: repo, resource: issue, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(**inputs)
        issue = inputs[:issue]
        state_reason = inputs[:state_reason]
        state_reason = nil if state_reason == "completed" # completed is only supported in the API, it is not a valid state_reason in the DB

        issue.async_repository.then do |repository|
          if !repository.has_issues?
            raise Errors::Unprocessable::IssuesDisabled.new
          end

          context[:permission].authorize_content(:issue, :update, repo: repository)

          state_reason_changing = state_reason != issue.state_reason

          if state_reason_changing && issue.close(context[:viewer], attributes: { state_reason: state_reason })
            { issue: issue }
          elsif issue.closed? || issue.close(context[:viewer])
            { issue: issue }
          else
            raise Errors::Unprocessable.new("Could not close the issue.")
          end
        end
      end
    end
  end
end
