# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all subscriptions and notifications for a thread
  class DeleteAllForThreadJob < MaintenanceBaseJob

    # Retry a few times if we are checking for the non-existence of a thread, but it exists
    # in case there's a race condition with it's deletion
    class ThreadStillExistsError < StandardError; end
    retry_on ThreadStillExistsError, wait: 3.seconds, attempts: 5

    resolve_tenant_context do |list_type, list_id|
      Notifications::TenantContext.resolve_tenant_for_list(list_type: list_type, list_id: list_id)
    end

    # list_type   - String newsies list type
    # list_id     - Integer newsies list id
    # thread_type - String newsies thread type
    # thread_id   - Integer newsies thread id
    # options
    #   ensure_thread_deleted: Boolean, default false, should the job check that the thread doesn't exist before doing cleanup?
    #                          This is optional as sometimes when we queue the job we know for sure the thread will
    #                          be deleted, but it may not have happened yet.
    def perform(list_type, list_id, thread_type, thread_id, ensure_thread_deleted: false)
      if ensure_thread_deleted
        if GitHub.flipper[:notifications_summaries_skip_delete_all_for_thread].enabled?
          if thread_exists?(list_type, list_id, thread_type, thread_id)
            GitHub.logger.info(<<~MSG)
              Expected thread object to not exist for
                <Newsies::List type=#{list_type.inspect} id=#{list_id.inspect}>
                <Newsies::Thread type=#{thread_type.inspect} id=#{thread_id.inspect}>
              but it exists.
            MSG

            return
          end
        else
          raise_if_thread_exists?(list_type, list_id, thread_type, thread_id)
        end
      end

      list = List.new(list_type, list_id)
      thread = Thread.new(thread_type, thread_id, list: list) # rubocop:disable GitHub/ThreadUse
      scopes_by_klass = {
        NotificationEntry => NotificationEntry.for_thread(thread),
        SavedNotificationEntry => SavedNotificationEntry.for_thread(thread),
      }


      scopes_by_klass.each do |klass, scope|
        GitHub.tracer.in_span("delete_all_by_class", kind: :internal, attributes: { "code.namespace" => klass.name, "gh.notifications.delete_all_by_class.item.count" => scope.count }) do
          scope.in_batches(of: BATCH_SIZE) do |batched_scope|
            klass.throttle_writes { batched_scope.delete_all }
          end
        end
      end

      thread_subscriptions = ThreadSubscription.for_thread(thread)
      GitHub.tracer.in_span("delete_all_thread_subscriptions", kind: :internal, attributes: { "gh.notifications.delete_all_thread_subscriptions.item.count" => thread_subscriptions.count }) do
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

    private

    def thread_exists?(list_type, list_id, thread_type, thread_id)
      if thread_type == "Grit::Commit"
        list = list_type.constantize.find_by_id(list_id)
        list.commits.find(thread_id) if list
      else
        thread_type.constantize.find_by_id(thread_id).present?
      end
    rescue GitRPC::ObjectMissing
      nil
    end

    def raise_if_thread_exists?(list_type, list_id, thread_type, thread_id)
      if thread_exists?(list_type, list_id, thread_type, thread_id)
        raise ThreadStillExistsError, <<~MSG
          Expected thread object to not exist for
            <Newsies::List type=#{list_type.inspect} id=#{list_id.inspect}>
            <Newsies::Thread type=#{thread_type.inspect} id=#{thread_id.inspect}>
          but it exists.
        MSG
      end
    end
  end
end
