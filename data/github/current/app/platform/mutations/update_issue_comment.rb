# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssueComment < Platform::Mutations::Base
      description "Updates an IssueComment object."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The ID of the IssueComment to modify.", required: true, loads: Objects::IssueComment, as: :comment
      argument :body, String, "The updated text of the comment.", required: true
      argument :body_version, String, "The hash of the comment body.  If supplied, the comment will only be updated if the body_version matches the current body_version of the comment.", visibility: :internal, required: false

      error_fields
      field :issue_comment, Objects::IssueComment, "The updated comment.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        issue_comment = comment
        permission.async_repo_and_org_owner(issue_comment).then do |repo, org|
          permission.access_allowed?(:update_issue_comment, repo: repo, resource: issue_comment, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(comment:, execution_errors:, **inputs)
        issue = comment.issue
        actor = context[:viewer]

        issue.skip_update_issue_orchestration = true

        context[:permission].authorize_content(:issue_comment, :update, issue: issue, repo: issue.repository)

        if !context[:actor].can_have_granular_permissions? && !comment.async_viewer_can_update?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to update the comment #{comment.global_relay_id}."
          raise Errors::Forbidden.new(message)
        end

        # Bots are unable to make duplicate events
        duplicate_events_enabled = !context[:integration]

        if inputs[:body_version] && comment.body_version != inputs[:body_version]
          message = "The comment #{comment.global_relay_id} has been modified since you last fetched it."
          raise Errors::StaleData.new(message)
        end

        saved = Issues::Comments.update_comment(comment, inputs[:body], context[:viewer], performed_via_integration: context[:integration])

        if saved && duplicate_events_enabled
          duplicate_issue_events = issue.build_duplicate_issue_events(context[:viewer], comment.duplicate_issues)
          duplicate_issue_events.each(&:save) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        if saved
          update_issue_orchestration = IssueOrchestration.update_issue!(issue: issue, actor: context[:viewer])
          update_issue_orchestration.execute!
        end

        if comment.valid?
          {
            issue_comment: comment,
            errors: [],
          }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(comment, execution_errors)
          {
            issue_comment: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(comment),
          }
        end
      end
    end
  end
end
