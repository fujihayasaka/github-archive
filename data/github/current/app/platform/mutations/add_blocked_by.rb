# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddBlockedBy < Platform::Mutations::Base
      description "Adds a 'blocked by' relationship to an issue."

      feature_flag :issue_dependencies
      visibility :under_development
      minimum_accepted_scopes ["public_repo"]

      # Loaders ensure user has at least read access to the issue and blocking issue.
      argument :issue_id, ID, "The ID of the issue to be blocked.", required: true, loads: Objects::Issue
      argument :blocking_issue_id, ID, "The ID of the issue that blocks the given issue.", required: true, loads: Objects::Issue

      field :issue, Objects::Issue, null: true, description: "The issue that is blocked."
      field :blocking_issue, Objects::Issue, null: true, description: "The issue that is blocking the given issue."
      error_fields

      def self.async_api_can_modify?(permission, issue:, **inputs)
        # Ensure user has at least triage access to the blocked by issue in order to mutate.
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(
            :triage_issue,
            resource: issue,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(issue:, blocking_issue:)
        user = context[:viewer]

        unless IssueDependenciesFeature.enabled?(issue.repository, actor: user)
          raise Platform::Errors::Forbidden.new("Adding blocking issues is not enabled for this issue.")
        end

        # Ensure issue updates are authorized depending on some user and repo attributes,
        # for example by checking if the repo is archived or locked.
        # See Issues::ContentAuthorizer for specific requirements.
        context[:permission].authorize_content(:issue, :update, issue: issue, repo: issue.repository)
        context[:permission].authorize_content(:issue, :update, issue: blocking_issue, repo: blocking_issue.repository)

        begin
          issue.add_blocked_by!(blocking_issue, user)
        rescue ActiveRecord::RecordInvalid => e
          raise Platform::Errors::Validation.new("An error occurred while adding the blocking issue to the issue. #{e.message}")
        end

        { issue: issue.reload, blocking_issue: blocking_issue.reload, errors: [] } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end
end
