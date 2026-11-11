# typed: true
# frozen_string_literal: true

module Newsies
  # Deletes all subscriptions and notifications for a thread (Issue, PR, Commit, etc.).
  # Removes NotificationEntry, SavedNotificationEntry, ThreadSubscription, and
  # NotificationSummary records.
  #
  # Enqueued by: Newsies::Service via GitHub.newsies.async_delete_all_for_thread.
  # Called when issues, releases, gists, discussions, repository advisories, check suites,
  # and vulnerability alerts are deleted.
  class DeleteAllForThreadJob < MaintenanceBaseJob
    use_replicas ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::NotificationsSummaries

    DOG_STATS_PREFIX = "active_job.newsies_delete_all_for_thread_job".freeze

    before_enqueue do |job|
      klass = job.arguments[2]
      GitHub.dogstats.increment("#{DOG_STATS_PREFIX}.before_enqueue", tags: [
        "thread_type:#{klass}"
      ])
    end

    after_perform do |job|
      klass = job.arguments[2]
      GitHub.dogstats.increment("#{DOG_STATS_PREFIX}.after_perform", tags: [
        "thread_type:#{klass}"
      ])
    end
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
      GitHub.logger.info("delete all threads", {
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.job.name" => self.class.name,
        "gh.job.id" => job_id,
        "gh.notifications.list.class" => list_type,
        "gh.notifications.list.id" => list_id,
        "gh.notifications.thread.class" => thread_type,
        "gh.notifications.thread.id" => thread_id,
      })
      list = List.new(list_type, list_id)
      thread = Thread.new(thread_type, thread_id, list: list) # rubocop:disable GitHub/ThreadUse

      delete_entries_for_thread(NotificationEntry, thread)
      delete_entries_for_thread(SavedNotificationEntry, thread)

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

    def delete_entries_for_thread(klass, thread)
      pairs = ActiveRecord::Base.connected_to(role: :reading) { klass.for_thread(thread).pluck(:user_id, :id) }
      pairs.group_by(&:first).each do |user_id, user_pairs|
        ids = user_pairs.map(&:last)
        GitHub.tracer.in_span("delete_all_by_class", kind: :internal, attributes: { "code.namespace" => klass.name, "gh.notifications.job.item.count" => ids.size }) do
          ids.each_slice(BATCH_SIZE) do |batch|
            klass.throttle_writes { klass.where(user_id: user_id, id: batch).delete_all }
          end
        end
      end
    end
  end
end
