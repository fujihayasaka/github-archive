# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveSubIssue < Platform::Mutations::Base
      # Metadata
      description "Removes a sub-issue from a given issue"
      visibility :public
      minimum_accepted_scopes ["public_repo"]
      # Inputs and loaders
      argument :issue_id, ID, "The id of the issue.", required: true, loads: Objects::Issue
      argument :sub_issue_id, ID, "The id of the sub-issue.", required: true, loads: Objects::Issue
      # Outputs and errors
      field :issue, Objects::Issue, "The parent of the sub-issue.", null: true
      field :sub_issue, Objects::Issue, "The sub-issue of the parent.", null: true
      error_fields

      # Authorization
      def self.async_api_can_modify?(permission, **inputs)
        issue = inputs[:issue]
        sub_issue = inputs[:sub_issue]

        permission.async_repo_and_org_owner(issue).then do |repo, org|
          # We just need an instance of SubIssue to check permissions against, so we temporarily create one
          # We don't try to find it since we're checking permissions, and the SubIssue model itself may not exist,
          # and the resolve method should decide best how to handle that condition
          temp_sub_issue = SubIssue.build(source_issue_id: issue.id, target_issue_id: sub_issue.id, source_repository_id: issue.repository_id)
          permission.access_allowed?(
            :remove_sub_issue,
            resource: temp_sub_issue,
            source_repository: repo,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Body
      def resolve(**args)
        user = context[:viewer]
        GitHub.context.push(actor_id: user.id) # ensure the actor_id is in context for things like GlobalInstrumenter
        issue = args[:issue]
        sub_issue = args[:sub_issue]

        begin
          unless SubIssuesFeature.enabled?(issue.repository)
            raise Platform::Errors::Forbidden.new("Sub-issues are not enabled for this repository.")
          end

          issue.remove_sub_issue!(sub_issue)
        rescue ActiveRecord::RecordNotDestroyed => e
          raise Platform::Errors::Unprocessable.new("An error occured while removing the sub-issue from the parent issue.")
        end

        context[:recalculate_sub_issues_summary_issue_id] = issue.id

        { issue: issue, sub_issue: sub_issue, errors: [] }
      end
    end
  end
end
