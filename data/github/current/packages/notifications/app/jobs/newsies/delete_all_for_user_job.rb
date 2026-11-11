# typed: true
# frozen_string_literal: true

module Newsies
  # Deletes all subscriptions and notifications for a user. Removes ListSubscription,
  # ThreadTypeSubscription, NotificationEntry, SavedNotificationEntry, CustomInbox,
  # and ThreadSubscription records along with their subscription events.
  #
  # Enqueued by: DestroyUserCallbacks during user deletion, and Newsies::Service
  # via GitHub.newsies.async_delete_all_for_user(user_id).
  class DeleteAllForUserJob < MaintenanceBaseJob
    use_replicas ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries

    # user_id - Integer user to act on
    def perform(user_id)
      scopes_by_klass = {
        ListSubscription => ListSubscription.for_user(user_id),
        ThreadTypeSubscription => ThreadTypeSubscription.for_user(user_id),
        NotificationEntry => NotificationEntry.for_user(user_id),
        SavedNotificationEntry => SavedNotificationEntry.for_user(user_id),
        CustomInbox => CustomInbox.where(user_id: user_id),
      }

      scopes_by_klass.each do |klass, scope|
        GitHub.tracer.in_span("delete_all_by_class", kind: :internal, attributes: { "code.namespace" => klass.name, "gh.notifications.job.item.count" => scope.size }) do
          scope.in_batches(of: BATCH_SIZE) do |batched_scope|
            with_write do
              klass.throttle { batched_scope.delete_all }
            end
          end
        end
      end

      thread_subscriptions = ThreadSubscription.for_user(user_id)
      GitHub.tracer.in_span("delete_all_thread_subscriptions", kind: :internal, attributes: { "gh.notifications.job.item.count" => thread_subscriptions.size }) do
        thread_subscriptions.in_batches(of: BATCH_SIZE) do |batched_scope|
          with_write do
            delete_thread_subscription_events(batched_scope.pluck(:id))
            ThreadSubscription.throttle { batched_scope.delete_all }
          end
        end
      end
    end
  end
end
