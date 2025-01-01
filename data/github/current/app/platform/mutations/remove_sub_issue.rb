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

        permission.async_repo_and_org_owner(issue).then do |repo, org|
          # check that parent has write access
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
