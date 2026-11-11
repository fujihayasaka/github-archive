# typed: true
# frozen_string_literal: true

# Recovers missing notification summaries for a specific user. Iterates through both
# NotificationEntry and SavedNotificationEntry scopes in batches of 100, checking for
# entries without summaries. For each missing summary, enqueues a RecoverNotificationSummaryJob.
# Time-limited to 60 seconds per execution, rescheduling itself for continuation if needed.
#
# Enqueued by: Newsies::Managers::Web (lib/newsies/managers/web.rb) when a mark operation
# fails due to missing summaries.
class RecoverNotificationSummariesForUserJob < ApplicationJob
  BATCH_SIZE = 100
  TIME_LIMIT = 60 # seconds
  ENTRY_SCOPES = [
    Newsies::NotificationEntry,
    Newsies::SavedNotificationEntry,
  ]

  LOCK_KEY = proc do |job|
    user_id = job.arguments.first[:user_id]

    "user:#{user_id}"
  end

  queue_as :summaries_maintenance

  locked_by key: LOCK_KEY, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  attr_accessor :timer

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # This job recovers missing notification summaries
  # so it doesn't need tenant context information
  exempt_from_tenant_context_requirement

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries

  around_perform do |job, block|
    GitHub::SafeTimer.timeout(TIME_LIMIT) do |timer|
      job.timer = timer
      block.call
    end
  end

  def perform(user_id:, start_id: 0, start_type: T.must(ENTRY_SCOPES.first).name)
    scopes_from(start_type).each do |scope|
      scope.for_user(user_id).in_batches(of: BATCH_SIZE, start: start_id).each do |entries|
        throttle(scope) do
          entries.includes(:notification_summary).each do |entry|
            if time_expired?
              clear_lock # make sure we can enqueue again
              self.class.perform_later(user_id: user_id, start_id: entry.id, start_type: scope.name)
              return
            end

            next if entry.notification_summary

            newsies_list = Newsies::List.to_object(entry.newsies_list)
            newsies_thread = Newsies::Thread.to_object(entry.newsies_thread)
            RecoverNotificationSummaryJob.perform_later(
              id: entry.summary_id,
              list_type: newsies_list.type,
              list_id: newsies_list.id,
              thread_type: newsies_thread.type,
              thread_id: newsies_thread.id,
            )
          end
        end
      end
      start_id = 0 # Make sure we start from 0 for the next scope independently of the initial one.
    end
  end

  def scopes_from(start_type)
    return ENTRY_SCOPES if start_type == T.must(ENTRY_SCOPES.first).name

    ENTRY_SCOPES.drop(1)
  end

  def throttle(scope, &block)
    scope.throttle do
      NotificationSummary.throttle(&block)
    end
  end

  def time_expired?
    timer&.expired?
  end
end
