# typed: true
# frozen_string_literal: true

module Newsies
  # Deletes all subscriptions and notifications for a user across multiple lists.
  # Uses optimized batch size of 100. Removes ListSubscription, ThreadTypeSubscription,
  # NotificationEntry, SavedNotificationEntry, and ThreadSubscription records.
  #
  # Enqueued by: Newsies::Service via GitHub.newsies.async_delete_all_for_user_and_lists,
  # Notifications::Subscriptions.async_delete_user_subscriptions_for_lists, and
  # CleanupListNotificationsJob after a user loses repository access.
  class DeleteAllForUserAndListsJob < MaintenanceBaseJob
    use_replicas ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries

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
          NotificationEntry.throttle_writes do
            scope.delete_all
          end
        end

        SavedNotificationEntry.for_user(user_id)
                              .for_lists(batched_lists)
                              .in_batches(of: batch_size) do |scope|
          SavedNotificationEntry.throttle_writes do
            scope.delete_all
          end
        end
      end
    end
  end
end
