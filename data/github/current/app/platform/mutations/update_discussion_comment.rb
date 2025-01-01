# typed: true
# frozen_string_literal: true
module Platform
  module Mutations
    class UpdateDiscussionComment < Platform::Mutations::Base
      description "Update the contents of a comment on a Discussion"

      minimum_accepted_scopes ["public_repo"]

      argument :comment_id, ID, "The Node ID of the discussion comment to update.",
        required: true, loads: Objects::DiscussionComment
      argument :body, String, "The new contents of the comment body.", required: true

      field :comment, Objects::DiscussionComment, "The modified discussion comment.", null: true
      error_fields

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        permission.async_repo_and_org_owner(comment).then do |repo, org|
          permission.access_allowed?(
            :edit_discussion_comment,
            repo: repo,
            current_org: org,
            resource: comment,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(execution_errors:, comment:, body:)
        # Set the actor so we can log a Hydro event about this comment being updated.
        comment.actor = context[:viewer]

        if comment.update_body(body, context[:viewer], performed_via_integration: context[:integration])
          { comment: comment, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(comment, execution_errors)
          { comment: nil, errors: Platform::UserErrors.mutation_errors_for_model(comment) }
        end
      end
    end
  end
end
