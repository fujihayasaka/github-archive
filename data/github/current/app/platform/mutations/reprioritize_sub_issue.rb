# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReprioritizeSubIssue < Platform::Mutations::Base
      # Metadata
      description "Reprioritizes a sub-issue to a different position in the parent list."
      visibility :public
      minimum_accepted_scopes ["public_repo"]
      # Inputs and loaders
      argument :issue_id, ID, "The id of the parent issue.", required: true, loads: Objects::Issue
      argument :sub_issue_id, ID, "The id of the sub-issue to reprioritize.", required: true, loads: Objects::Issue
      argument :after_id, ID, "The id of the sub-issue to be prioritized after (either positional argument after OR before should be specified).", required: false, loads: Objects::Issue
      argument :before_id, ID, "The id of the sub-issue to be prioritized before (either positional argument after OR before should be specified).", required: false, loads: Objects::Issue

      # Outputs and errors
      field :issue, Objects::Issue, "The parent issue that the sub-issue was reprioritized in.", null: true
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
        issue = args[:issue]
        before = args[:before]
        after = args[:after]
        sub_issue = args[:sub_issue]

        unless SubIssuesFeature.enabled?(issue.repository)
          raise Platform::Errors::Forbidden.new("Sub-issues are not enabled for this repository.")
        end

        raise Errors::Validation.new("Either a beforeId or afterId argument must be provided.") unless before.present? || after.present?
        raise Errors::Validation.new("Only the beforeId or the afterId argument may be provided, but not both.") if before.present? && after.present?
        raise Errors::Validation.new("Provided sub-issue is not a sub-issue of the provided parent.") unless sub_issue.parent_issue_relation&.source_issue_id == issue.id

        prioritization_args = if before.present?
          { before: before.parent_issue_relation }
        else
          { after: after.parent_issue_relation }
        end

        unless prioritization_args.values.first&.source_issue_id == issue.id
          raise Errors::Validation.new("Provided positional argument is not a sub-issue of the provided parent.")
        end

        issue.prioritize_dependent!(sub_issue.parent_issue_relation, **prioritization_args)

        { issue: issue.reload, errors: [] }
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        raise Errors::ServiceUnavailable.new("Parent sub-issue list is temporarily locked for maintenance. Please try again.")
      end
    end
  end
end
