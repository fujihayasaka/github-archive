# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteDiscussionComment < Platform::Mutations::Base
      description "Delete a discussion comment. If it has replies, wipe it instead."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The Node id of the discussion comment to delete.", required: true,
        loads: Objects::DiscussionComment, as: :comment

      field :comment, Objects::DiscussionComment, "The discussion comment that was just deleted.", null: true
      error_fields

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        permission.async_repo_and_org_owner(comment).then do |repo, org|
          permission.access_allowed?(
            :delete_discussion_comment,
            repo: repo,
            current_org: org,
            resource: comment,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(execution_errors:, comment:)
        # Load another ActiveRecord instance of the comment we're about to delete.
        # Preload its parent_comment association, in case #wipe_or_destroy triggers :delete_wiped_parent_if_no_children
        # and its (wiped) parent comment is deleted, too.
        snapshot = DiscussionComment.find(comment.id)
        snapshot.parent_comment

        if comment.wipe_or_destroy(context[:viewer])
          # If we are returning a snapshot we should make sure the values resemble the new state of the data to match
          # what would be in the database if we were to wipe the comment to ensure consistency from this API.
          unless comment.wiped?
            snapshot.body = ""
            snapshot.deleted_at = Time.current.utc
          end

          { comment: comment.wiped? ? comment : snapshot, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(comment, execution_errors)
          { comment: nil, errors: Platform::UserErrors.mutation_errors_for_model(comment) }
        end
      end
    end
  end
end
