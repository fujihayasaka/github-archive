# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all subscriptions and notifications for a list and a given set of users
  class DeleteAllForListAndUsersJob < MaintenanceBaseJob
    # list_type - String newsies list type
    # list_id   - Integer newsies list id
    # user_ids   - Array of Integer user ids

    resolve_tenant_context do |list_type, list_id, _|
      Notifications::TenantContext.resolve_tenant_for_list(list_type: list_type, list_id: list_id)
    end

    def perform(list_type, list_id, user_ids)
      list = List.new(list_type, list_id)
      trace_attributes = {
        "gh.notifications.list.id" => list_id,
        "gh.notifications.list.type" => list_type,
        "gh.notifications.job.user.count" => user_ids.size
      }

      GitHub.tracer.in_span("perform", kind: :internal, attributes: trace_attributes) do

        user_ids.each_slice(BATCH_SIZE) do |batched_user_ids|
          GitHub.tracer.in_span("list_subscription", kind: :internal) do
            with_write do
              ListSubscription.throttle do
                ListSubscription.for_list(list).for_users(batched_user_ids).delete_all
              end
            end
          end

          GitHub.tracer.in_span("delete_thread_type_subscriptions", kind: :internal) do
            with_write do
              ThreadTypeSubscription.throttle do
                ThreadTypeSubscription.for_list(list).for_users(batched_user_ids).delete_all
              end
            end
          end

          GitHub.tracer.in_span("delete_thread_subscriptions", kind: :internal) do
            ThreadSubscription.for_list(list)
                              .for_users(batched_user_ids)
                              .in_batches(of: BATCH_SIZE) do |batched_scope|
              with_write do
                delete_thread_subscription_events(batched_scope.pluck(:id))
                ThreadSubscription.throttle { batched_scope.delete_all }
              end
            end
          end

          GitHub.tracer.in_span("delete_notification_entries", kind: :internal) do
            NotificationEntry.for_list(list)
                             .for_users(batched_user_ids)
                             .in_batches(of: BATCH_SIZE) do |scope|
              with_write do
                NotificationEntry.throttle { scope.delete_all }
              end
            end
          end

          GitHub.tracer.in_span("delete_saved_notification_entries", kind: :internal) do
            SavedNotificationEntry.for_list(list)
                                  .for_users(batched_user_ids)
                                  .in_batches(of: BATCH_SIZE) do |scope|
              with_write do
                SavedNotificationEntry.throttle { scope.delete_all }
              end
            end
          end
        end
      end
    end
  end
end
