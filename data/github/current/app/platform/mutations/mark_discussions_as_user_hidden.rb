# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkDiscussionsAsUserHidden < Platform::Mutations::Base
      description "Mark discussions as user hidden."

      minimum_accepted_scopes ["public_repo"]

      visibility :internal

      # The user object is intentionally not loaded because it is expected to be nil.
      argument :user_id, Integer, "The id of the author whose discussion should be marked as user-hidden.", required: true

      field :total_count, Integer, "The total number of discussions found for the user.", null: true
      field :total_updated, Integer, "The number of discussions that were successfully marked as user-hidden.", null: true
      field :errors, [String], "Any errors that occurred during the mutation.", null: true

      BATCH_SIZE = 500

      # Default to allowing through requests only if the mutation is
      # `:internal` and the current request is not a GraphQL API request
      def self.async_api_can_modify?(permission, **_)
        permission.hidden_from_public?(self)
      end

      def resolve(user_id:)
        # Favors the `user_id` primitive over the User ActiveRecord from the (argument) `loads:` option,
        # because if the User no longer exists, we would lose the reference to user_id and would no longer
        # be able to hide the associated Discussions for the deleted (spammy) user.
        user = Loaders::ActiveRecord.load(::User, user_id).sync
        scope = Discussion.where(user_id:, user_hidden: false)

        if user.present?
          GitHub.dogstats.increment("discussions.mark_as_user_hidden.failed", tags: ["user:present"])
          return { errors: ["User must be in a deleted state. No discussions were hidden."] }
        end

        total_updated = 0
        total_count = scope.count # Cache the count to ensure a consistent pre-update value and avoid extra queries.
        GitHub.dogstats.gauge("discussions.mark_as_user_hidden.total.count", total_count)
        total_updated = mark_discussions_as_hidden_with_updated_count(scope)
        { total_count:, total_updated: }
      rescue StandardError => error
        Failbot.report(error, "gh.user.id": user_id) # This shouldn't occur, let's report it!
        GitHub.dogstats.increment("discussions.mark_as_user_hidden.failed", tags: ["status:error"])

        {
          total_count:,
          total_updated:,
          errors: ["An error occurred while hiding discussions for user id: #{user_id}"]
        }
      end

      private

      def mark_discussions_as_hidden_with_updated_count(scope)
        total_updated = 0

        Discussion.throttle_writes do
          scope.in_batches(of: BATCH_SIZE) do |batch|
            total_updated += batch.update_all(user_hidden: true)
          end
        end

        GitHub.dogstats.gauge("discussions.mark_as_user_hidden.update.count", total_updated)
        total_updated
      end
    end
  end
end
