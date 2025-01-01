# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all subscriptions and notifications for a user and a given set of lists
  class DeleteAllForUserAndListsJob < MaintenanceBaseJob

    # Optimized batch = 100 for GHES. This change brings alignment for GHEC and GHES https://github.com/github/github/pull/346246
    OPTIMIZED_BATCH_SIZE = 100

    # user_id - Integer user to act on
    # lists   - Array of hashes: [ { type: "Repository", id: 1}, ...]
    def perform(user_id, list_hashes)
      lists = list_hashes.map { |l| List.new(l[:type], l[:id]) }
      batch_size = OPTIMIZED_BATCH_SIZE

      lists.each_slice(batch_size) do |batched_lists|
        with_write do
          ListSubscription.throttle do
            ListSubscription.for_user(user_id).for_lists(batched_lists).delete_all
          end

          ThreadTypeSubscription.throttle do
            ThreadTypeSubscription.for_user(user_id).for_lists(batched_lists).delete_all
          end
        end

        ThreadSubscription.for_user(user_id)
                          .for_lists(batched_lists)
                          .in_batches(of: batch_size) do |batched_scope|
          with_write do
            # this calls the base class which is another delete using batches of 10
            delete_thread_subscription_events(batched_scope.pluck(:id), batch_size: OPTIMIZED_BATCH_SIZE)
            ThreadSubscription.throttle { batched_scope.delete_all }
          end
        end

        NotificationEntry.for_user(user_id)
                         .for_lists(batched_lists)
                         .in_batches(of: batch_size) do |scope|
          with_write { NotificationEntry.throttle { scope.delete_all } }
        end

        SavedNotificationEntry.for_user(user_id)
                              .for_lists(batched_lists)
                              .in_batches(of: batch_size) do |scope|
          with_write { SavedNotificationEntry.throttle { scope.delete_all } }
        end
      end
    end
  end
end
