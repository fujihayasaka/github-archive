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
        sub_issue = inputs[:sub_issue]

        permission.async_repo_and_org_owner(issue).then do |repo, org|
          # We just need an instance of SubIssue to check permissions against, so we temporarily create one
          # We don't try to find it since we're checking permissions, and the SubIssue model itself may not exist,
          # and the resolve method should decide best how to handle that condition
          temp_sub_issue = SubIssue.build(source_issue_id: issue.id, target_issue_id: sub_issue.id, source_repository_id: issue.repository_id)
          permission.access_allowed?(
            :update_sub_issue,
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
        issue = args[:issue]
        before = args[:before]
        after = args[:after]
        sub_issue = args[:sub_issue]

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

        check_database_resource_update_rate_limit!(resource: issue, current_user: context[:viewer])

        issue.prioritize_dependent!(sub_issue.parent_issue_relation, **prioritization_args)

        { issue: issue.reload, errors: [] } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        raise Errors::ServiceUnavailable.new("Parent sub-issue list is temporarily locked for maintenance. Please try again.")
      end
    end
  end
end
