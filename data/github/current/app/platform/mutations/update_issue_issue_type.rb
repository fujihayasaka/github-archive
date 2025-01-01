# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssueIssueType < Platform::Mutations::Base
      description "Updates the issue type on an issue"
      graphql_name "UpdateIssueIssueType"

      minimum_accepted_scopes ["repo"]

      error_fields

      extras [:execution_errors]

      argument :issue_type_id, ID, "The ID of the issue type to update on the issue", required: false

      argument :issue_id, ID, "The ID of the issue to update", loads: Objects::Issue, required: true

      field :issue, Objects::Issue, "The updated issue", null: true

      def self.async_api_can_modify?(permission, issue:, **inputs)
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(
            :triage_issue,
            resource: issue,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            prevent_author: true,
          )
        end
      end

      def resolve(issue:, execution_errors:, **inputs)
        issue_type = Helpers::IssueTypes.load_by_id(arguments[:issue_type_id], context) if arguments[:issue_type_id].present?

        issue.async_repository.then do |repository|
          unless repository.has_issues?
            raise Errors::Forbidden, "Repository has issues disabled."
          end

          context[:permission].authorize_content(:issue, :update, issue: issue, repo: repository)

          if context[:permission].integration_user_request?
            issue.performed_via_integration = context[:integration]
            issue.modifying_integration = context[:integration]
          end

          issue.issue_type = issue_type

          next { issue: issue, errors: [] } if issue.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)

          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue, execution_errors)
          { issue: nil, errors: Platform::UserErrors.mutation_errors_for_model(issue, translate: { repository_id: "issueTypeId" }) }

        end
      end
    end
  end
end
