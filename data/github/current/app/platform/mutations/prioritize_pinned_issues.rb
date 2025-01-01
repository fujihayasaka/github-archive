# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PrioritizePinnedIssues < Platform::Mutations::Base
      description "Prioritize issues pinned to a repository"
      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The ID of the repository where issues are pinned.", required: true, loads: Objects::Repository
      argument :issue_ids, [ID], "IDs of issues that are pinned, in order. This list must contains between 2 and 3 IDs.", required: true, loads: Objects::Issue

      field :repository, Objects::Repository, "The updated repository", null: true

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:prioritize_pinned_issues, repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(repository:, issues:)
        viewer = context[:viewer]

        validate_inputs(repository, issues, viewer)
        repository.reorder_pinned_issues(issues.map(&:id))

        { repository: repository, errors: [] }
      end

      def validate_inputs(repository, issues, viewer)
        raise Errors::Unprocessable::IssuesDisabled.new unless repository.has_issues?
        raise Errors::Unprocessable::RepositoryMigration.new if repository.locked_on_migration?
        raise Errors::Unprocessable::RepositoryArchived.new if repository.archived?
        raise Errors::Forbidden.new("Actor must be writer of repository") unless repository.can_pin_issues?(viewer)
        raise Errors::Validation.new("At least 2 issues must be given as input") if issues.length < 2
        raise Errors::Validation.new("Only 3 issues can be pinned") if issues.length > Repository::PinnedIssuesDependency::PINNED_ISSUES_LIMIT
        raise Errors::Validation.new("An issue is does not belong to the repository") if issues.any? { |issue| issue.repository_id != repository.id }

        existing_pinned_issues_ids = repository.pinned_issues.map(&:issue_id)
        if issues.map(&:id).any? { |id| !existing_pinned_issues_ids.include?(id) }
          raise Errors::Validation.new("An issue is not be pinned to the repository")
        end
      end
    end
  end
end
