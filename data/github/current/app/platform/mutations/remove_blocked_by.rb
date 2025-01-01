# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveBlockedBy < Platform::Mutations::Base
      description "Removes a 'blocked by' relationship from an issue."

      visibility :public
      minimum_accepted_scopes ["public_repo"]

      # Loaders ensure user has at least read access to the issue and blocking issue.
      argument :issue_id, ID, "The ID of the blocked issue.", required: true, loads: Objects::Issue
      argument :blocking_issue_id, ID, "The ID of the blocking issue.", required: true, loads: Objects::Issue

      field :issue, Objects::Issue, null: true, description: "The previously blocked issue."
      field :blocking_issue, Objects::Issue, null: true, description: "The previously blocking issue."
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
        unless IssueDependenciesFeature.enabled?(issue.repository, actor: context[:viewer])
          raise Platform::Errors::Forbidden.new("Removing blocking issues is not enabled for this issue.")
        end

        # Ensure issue updates are authorized depending on some user and repo attributes,
        # for example by checking if the repo is archived or locked.
        # See Issues::ContentAuthorizer for specific requirements.
        context[:permission].authorize_content(:issue, :update, issue: issue, repo: issue.repository)
        context[:permission].authorize_content(:issue, :update, issue: blocking_issue, repo: blocking_issue.repository)

        begin
          issue.remove_blocked_by!(blocking_issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        rescue ActiveRecord::RecordNotDestroyed => e
          raise Platform::Errors::Unprocessable.new("An error occurred while removing the blocking issue from the issue. #{e.message}")
        end

        { issue: issue.reload, blocking_issue: blocking_issue.reload, errors: [] } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end
end
