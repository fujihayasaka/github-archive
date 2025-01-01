# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all subscriptions and notifications for a user
  class DeleteAllForUserJob < MaintenanceBaseJob
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
