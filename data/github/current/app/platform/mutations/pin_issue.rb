# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PinIssue < Platform::Mutations::Base
      description "Pin an issue to a repository"

      minimum_accepted_scopes ["public_repo"]

      argument :issue_id, ID, "The ID of the issue to be pinned", required: true, loads: Objects::Issue

      field :issue, Objects::Issue, "The issue that was pinned", null: true
      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue:, **inputs)
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(:pin, repo: repo, resource: issue, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(issue:)
        viewer = context[:viewer]

        issue.async_repository.then do |repository|
          if !repository.has_issues?
            raise Errors::Unprocessable::IssuesDisabled.new
          end

          if repository.locked_on_migration?
            raise Errors::Unprocessable::RepositoryMigration.new
          end

          if repository.archived?
            raise Errors::Unprocessable::RepositoryArchived.new
          end

          unless issue.repository.can_pin_issues?(viewer)
            raise Errors::Forbidden.new("Actor must be writer of repository")
          end

          if repository.pinned_issues&.count >= Repository::PinnedIssuesDependency::PINNED_ISSUES_LIMIT
            raise Errors::Unprocessable.new("Maximum 3 pinned issues per repository")
          end

          if issue.pin(actor: viewer)
            {
              issue: issue,
              errors: {},
            }
          else
            raise Errors::Unprocessable.new("The issue is already pinned or could not be pinned at this time")
          end
        end
      end
    end
  end
end
