# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PinIssueComment < Platform::Mutations::Base
      docs_category :issues
      description "Pins an Issue Comment."
      minimum_accepted_scopes ["public_repo"]

      error_fields

      argument :issue_comment_id, ID, "The ID of the Issue Comment to pin. Comment pinning is not supported on Pull Requests.", required: true, loads: Objects::IssueComment

      field :issue_comment, Objects::IssueComment, "The Issue Comment that was pinned", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue_comment:, **inputs)
        permission.async_repo_and_org_owner(issue_comment).then do |repo, org|
          permission.access_allowed?(
            :pin_issue_comment,
            repo:,
            resource: issue_comment,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(issue_comment:, execution_errors:)
        repository = issue_comment.repository
        actor = context[:viewer]

        result = Issues.domain.comments.pin(
          issue_comment:,
          actor:,
        )

        case result
        when GH::Result::Ok
          {
            issue_comment: result.value.issue_comment,
            errors: []
          }
        when GH::Result::Error::Validation
          message = result.model.errors.full_messages.join(", ")
          Platform::UserErrors.append_legacy_mutation_error_messages_to_context([message], execution_errors)
          { issue_comment: nil, errors: Platform::UserErrors.mutation_errors_for_model(result.model, translate: { issue: "issueCommentId", issue_comment: "issueCommentId" }) }
        when GH::Result::Error
          raise Errors::ServiceUnavailable.new("Encountered an error while pinning the Issue Comment: #{result.message}")
        end
      end
    end
  end
end
