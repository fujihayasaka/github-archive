# typed: true
# frozen_string_literal: true

module Newsies
  # (Un)marks notifications as sapmmy for a given thread
  class UpdateNotificationsSpamStatusJob < MaintenanceBaseJob
    class UnableToLockThread < GitHub::Restraint::UnableToLock; end

    LOCK_RETRY_TTL = 5.minutes

    retry_on UnableToLockThread, wait: LOCK_RETRY_TTL

    around_perform do |job, block|
      # This job is also lock-restrained by MaintenanceBaseJob.
      # MaintenanceBaseJob lock is applied first and then per thread lock.
      #
      # In order to prevent `retry_on` from MaintenanceBaseJob being overridden
      # in this class we rescue and raise a different exception and be explicit
      # about the behavior.
      list_type, list_id, thread_type, thread_id = job.arguments
      list = List.new(list_type, list_id)
      thread = Thread.new(thread_type, thread_id, list: list) # rubocop:disable GitHub/ThreadUse
      result = :failure

      GitHub.logger.with_named_tags(
        "code.namespace": self.class.name,
        "gh.notifications.list.type": list_type,
        "gh.notifications.list.id": list_id,
        "gh.notifications.thread.type": thread_type,
        "gh.notifications.thread.id": thread_id,
      ) do
        GitHub::Restraint.new.lock!("update-notifications-spam-status-#{list.key}-#{thread.key}", 1, LOCK_RETRY_TTL) do
          block.call
        end

        result = :success
      rescue GitHub::Restraint::UnableToLock
        raise UnableToLockThread
      ensure
        GitHub.logger.info("Acquiring lock for notifications spam status for a thread", "code.function": "around_perform", "gh.notifications.result": result.to_s)
        GitHub.dogstats.increment("notifications.update_spam_status.count", tags: %W[list_type:#{list_type} thread_type:#{thread_type} result:#{result}])
      end
    end

    # list_type   - String newsies list type
    # list_id     - Integer newsies list id
    # thread_type - String newsies thread type
    # thread_id   - Integer newsies thread id
    def perform(list_type, list_id, thread_type, thread_id)
      thread_subject = thread_type.constantize.find_by_id(thread_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      is_thread_spammy = thread_subject&.respond_to?(:spammy?) && thread_subject.spammy?
      list = List.new(list_type, list_id)
      thread = Thread.new(thread_type, thread_id, list: list) # rubocop:disable GitHub/ThreadUse

      trace_attributes = { "gh.notifications.thread.id" => thread.id, "gh.notifications.thread.spammy" => is_thread_spammy }
      operation = is_thread_spammy ? :marking_as_spam : :restoring
      GitHub.logger.info("updating spam status", "code.function": "perform", "gh.notifications.operation": operation.to_s)
      GitHub.dogstats.increment("notifications.update_spam_status.operation_count", tags: %W[operation:#{operation} list_type:#{list_type} thread_type:#{thread_type}])
      GitHub.tracer.in_span("move_notification_entries", kind: :internal, attributes: trace_attributes) do
        move_notification_entries(
          thread: thread,
          source_class: is_thread_spammy ? NotificationEntry : SpammyNotificationEntry,
          destination_class: is_thread_spammy ? SpammyNotificationEntry : NotificationEntry,
          ignore_duplicates: !is_thread_spammy,
        )
      end
    end

    private

    def move_notification_entries(thread:, source_class:, destination_class:, ignore_duplicates:)
      columns = (source_class.columns.map(&:name) & destination_class.columns.map(&:name))

      source_class.for_thread(thread).select(columns).in_batches(of: BATCH_SIZE) do |batched_scope|
        values = batched_scope.map(&:attributes)

        destination_class.throttle_writes do
          if ignore_duplicates
            GitHub.tracer.in_span("insert_all", kind: :internal) do
              destination_class.insert_all(values)
            end
          else
            GitHub.tracer.in_span("upsert_all", kind: :internal) do
              destination_class.upsert_all(values)
            end
          end
        end

        GitHub.tracer.in_span("delete_all", kind: :internal) do
          source_class.throttle_writes { batched_scope.delete_all }
        end
      end
    end
  end
end
