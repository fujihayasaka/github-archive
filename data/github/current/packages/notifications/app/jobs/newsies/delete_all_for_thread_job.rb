# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all subscriptions and notifications for a thread
  class DeleteAllForThreadJob < MaintenanceBaseJob
    use_replicas ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::NotificationsSummaries

    resolve_tenant_context do |list_type, list_id|
      # We only need to connect to Repositories in the event of tenant context resolution, which
      # only happens in some environments like Proxima.
      ActiveRecord::Base.connected_to_many([ApplicationRecord::Repositories], role: :reading) do
        Notifications::TenantContext.resolve_tenant_for_list(list_type: list_type, list_id: list_id)
      end
    end

    # list_type   - String newsies list type
    # list_id     - Integer newsies list id
    # thread_type - String newsies thread type
    # thread_id   - Integer newsies thread id
    #
    # NOTE: The option ensure_thread_deleted has been deprecated and doesn't do anything.
    #   For the moment it is still defined until we make sure all enqueued jobs don't include
    #   the option in the parameters list
    def perform(list_type, list_id, thread_type, thread_id, ensure_thread_deleted: false)
      list = List.new(list_type, list_id)
      thread = Thread.new(thread_type, thread_id, list: list) # rubocop:disable GitHub/ThreadUse
      scopes_by_klass = {
        NotificationEntry => NotificationEntry.for_thread(thread),
        SavedNotificationEntry => SavedNotificationEntry.for_thread(thread),
      }

      scopes_by_klass.each do |klass, scope|
        GitHub.tracer.in_span("delete_all_by_class", kind: :internal, attributes: { "code.namespace" => klass.name, "gh.notifications.job.item.count" => scope.count }) do
          scope.in_batches(of: BATCH_SIZE) do |batched_scope|
            klass.throttle_writes { batched_scope.delete_all }
          end
        end
      end

      thread_subscriptions = ThreadSubscription.for_thread(thread)
      GitHub.tracer.in_span("delete_all_thread_subscriptions", kind: :internal, attributes: { "gh.notifications.job.item.count" => thread_subscriptions.count }) do
        thread_subscriptions.in_batches(of: BATCH_SIZE) do |batched_scope|
          delete_thread_subscription_events(batched_scope.pluck(:id))
          ThreadSubscription.throttle_writes { batched_scope.delete_all }
        end
      end

      NotificationSummary.throttle_writes do
        GitHub.tracer.in_span("delete_notification_summary", kind: :internal) do
          NotificationSummary.by_thread(list, thread)&.delete
        end
      end
    end
  end
end
