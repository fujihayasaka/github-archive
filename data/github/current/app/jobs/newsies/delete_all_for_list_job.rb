# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all subscriptions and notifications for a list
  class DeleteAllForListJob < MaintenanceBaseJob
    # list_type - String newsies list type
    # list_id   - Integer newsies list id

    resolve_tenant_context do |list_type, list_id|
      Notifications::TenantContext.resolve_tenant_for_list(list_type: list_type, list_id: list_id)
    end

    def perform(list_type, list_id)
      list = List.new(list_type, list_id)
      scopes_by_klass = {
        ListSubscription => ListSubscription.for_list(list),
        ThreadTypeSubscription => ThreadTypeSubscription.for_list(list),
        NotificationEntry => NotificationEntry.for_list(list),
        SavedNotificationEntry => SavedNotificationEntry.for_list(list),
      }

      batch_size = BATCH_SIZE
      scopes_by_klass.each do |klass, scope|
        batch_size = 100 if klass == NotificationEntry

        GitHub.tracer.in_span("delete_all_by_class", kind: :internal, attributes: { "code.namespace" => klass.name, "gh.notifications.delete_all_by_class.item.count" => scope.size }) do
          scope.in_batches(of: batch_size) do |batched_scope|
            klass.throttle_writes { batched_scope.delete_all }
          end
        end
      end

      thread_subscriptions = ThreadSubscription.for_list(list)
      GitHub.tracer.in_span("delete_all_thread_subscriptions", kind: :internal, attributes: { "gh.notifications.delete_all_thread_subscriptions.item.count" => thread_subscriptions.size }) do
        thread_subscriptions.in_batches(of: BATCH_SIZE) do |batched_scope|
          delete_thread_subscription_events(batched_scope.pluck(:id))
          ThreadSubscription.throttle_writes { batched_scope.delete_all }
        end
      end
    end
  end
end
