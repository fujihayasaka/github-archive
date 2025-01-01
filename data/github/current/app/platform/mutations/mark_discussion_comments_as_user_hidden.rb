# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkDiscussionCommentsAsUserHidden < Platform::Mutations::Base
      description "Mark discussion comments as user hidden."

      minimum_accepted_scopes ["public_repo"]

      visibility :internal

      # The user object is intentionally not loaded because it is expected to be nil
      # and we don't need the discussion object either, as we only need to update its associated comments.
      argument :discussion_id, Integer, "The id of the discussion whose comments should be marked as user-hidden.", required: true
      argument :user_id, Integer, "The id of the author whose comments for the given discussion should be marked as user-hidden.", required: true

      field :total_count, Integer, "The total number of available comments found for the user in the discussion.", null: true
      field :total_updated, Integer, "The number of comments that were successfully marked as user-hidden in the discussion.", null: true
      field :errors, [String], "Any errors that occurred during the mutation.", null: true

      BATCH_SIZE = 500

      # Default to allowing through requests only if the mutation is
      # `:internal` and the current request is not a GraphQL API request
      def self.async_api_can_modify?(permission, **_)
        permission.hidden_from_public?(self)
      end

      def resolve(discussion_id:, user_id:)
        # Favors the `user_id` primitive over the User ActiveRecord from the (argument) `loads:` option,
        # because if the User no longer exists, we would lose the reference to user_id and would no longer
        # be able to hide the associated Discussion comments for the deleted (spammy) user.
        user = Loaders::ActiveRecord.load(::User, user_id).sync
        scope = DiscussionComment.where(user_id:, discussion_id:, user_hidden: false, deleted_at: nil) # Only non-deleted comments can be hidden.

        if user.present?
          GitHub.dogstats.increment("discussion_comments.mark_as_user_hidden.failed", tags: ["user:present"])
          return { errors: ["User must be in a deleted state. No discussion comments were hidden."] }
        end

        total_updated = 0
        total_count = scope.count # Cache the count to ensure a consistent pre-update value and avoid extra queries.

        GitHub.dogstats.gauge("discussion_comments.mark_as_user_hidden.total.count", total_count)
        total_updated = mark_discussion_comments_as_hidden_with_updated_count(scope)

        { total_count:, total_updated: }
      rescue StandardError => error
        Failbot.report(error, "gh.discussion.id": discussion_id, "gh.user.id": user_id) # This shouldn't occur, let's report it!
        GitHub.dogstats.increment("discussion_comments.mark_as_user_hidden.failed", tags: ["status:error"])

        {
          total_count:,
          total_updated:,
          errors: ["An error occurred while hiding discussion comments discussion id: #{discussion_id}"]
        }
      end

      private

      def mark_discussion_comments_as_hidden_with_updated_count(scope)
        total_updated = 0

        DiscussionComment.throttle_writes do
          scope.in_batches(of: BATCH_SIZE) do |batch|
            total_updated += batch.update_all(user_hidden: true)
          end
        end

        GitHub.dogstats.gauge("discussion_comments.mark_as_user_hidden.comments.updated", total_updated)
        total_updated
      end
    end
  end
end
