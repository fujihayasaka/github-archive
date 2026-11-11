# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddDiscussionComment < Platform::Mutations::Base
      description "Adds a comment to a Discussion, possibly as a reply to another comment."

      minimum_accepted_scopes ["public_repo"]

      argument :discussion_id, ID, "The Node ID of the discussion to comment on.",
        required: true, loads: Objects::Discussion
      argument :reply_to_id, ID, "The Node ID of the discussion comment within this discussion to reply to.",
        required: false, loads: Objects::DiscussionComment
      argument :body, String, "The contents of the comment.", required: true

      field :comment, Objects::DiscussionComment, "The newly created discussion comment.", null: true
      error_fields

      extras [:execution_errors]

      # Map Rails model attribute names to the argument names of this mutation.
      PATH_TRANSLATIONS = {
        parent_comment: "replyToId",
      }.freeze

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, discussion:, **inputs)
        permission.async_repo_and_org_owner(discussion).then do |repo, org|
          permission.access_allowed?(
            :create_discussion_comment,
            repo: repo,
            current_org: org,
            resource: discussion,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(execution_errors:, discussion:, body:, reply_to: nil)
        comment = discussion.comments.build(
          user: context[:viewer],
          body: body,
          parent_comment: reply_to,
        )

        if context[:permission].integration_user_request?
          comment.performed_via_integration = context[:integration]
        end

        if comment.save
          # Reload to pick up updated :total_upvotes field
          { comment: comment.reload, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(comment, execution_errors)
          { comment: nil, errors: Platform::UserErrors.mutation_errors_for_model(comment, translate: PATH_TRANSLATIONS) }
        end
      end
    end
  end
end
