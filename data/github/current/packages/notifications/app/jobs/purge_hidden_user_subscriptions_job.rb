# typed: strict
# frozen_string_literal: true

# Scheduled job that iterates over the `hidden_users` table and purges
# notification subscriptions for users who have been hidden (spammy) for
# longer than the retention period.  Uses a durable cursor in
# Notifications::KV to survive restarts and picks up where it left off.
class PurgeHiddenUserSubscriptionsJob < ApplicationJob
  CURSOR_KEY = "purge_hidden_user_subscriptions.cursor_id"
  RETENTION_PERIOD = T.let(90.days, ActiveSupport::Duration)
  BATCH_SIZE = 500
  MAX_RUNTIME = T.let(4.minutes, ActiveSupport::Duration)
  MAX_QUEUE_DEPTH = 50_000
  QUEUE_CHECK_INTERVAL = T.let(30.seconds, ActiveSupport::Duration)
  INTERVAL = T.let(5.minutes, ActiveSupport::Duration)
  LOCK_TIMEOUT = T.let(MAX_RUNTIME + 2.minutes, ActiveSupport::Duration)

  schedule interval: INTERVAL, condition: -> { !GitHub.enterprise? }
  locked_by timeout: LOCK_TIMEOUT, key: DEFAULT_LOCK_PROC
  queue_as :subscriptions_maintenance
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  exempt_from_tenant_context_requirement

  use_replicas ApplicationRecord::Mysql1, ApplicationRecord::Mysql2, ApplicationRecord::Repositories

  sig { void }
  def perform
    cursor_id = Notifications::KV.store.get(CURSOR_KEY).value { "0" }.to_i
    end_at = Time.current + MAX_RUNTIME
    users_processed_this_run = 0
    last_queue_check = T.let(Time.at(0), Time)

    while Time.current < end_at
      if Time.current - last_queue_check >= QUEUE_CHECK_INTERVAL
        depth = self.class.queue_depth(queue: :notifications_maintenance)
        if depth > MAX_QUEUE_DEPTH
          GitHub.dogstats.increment("purge_hidden_user_subscriptions.backpressure_pause")
          break
        end
        last_queue_check = Time.current
      end

      rows = Newsies::HiddenUser
        .where("created_at < ?", RETENTION_PERIOD.ago)
        .where("id > ?", cursor_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .pluck(:id, :user_id)

      break if rows.empty?

      batch_error = T.let(false, T::Boolean)
      rows.each do |hidden_user_id, user_id|
        begin
          delete_subscriptions_for_user(user_id)
        rescue StandardError => e
          GitHub.dogstats.increment("purge_hidden_user_subscriptions.user_error")
          GitHub.logger.warn("Failed to purge subscriptions for hidden user", {
            "code.namespace" => "PurgeHiddenUserSubscriptionsJob",
            "gh.user.id" => user_id,
            "error.class" => e.class.name,
            "error.message" => e.message,
          })
          NotificationsFailbot.report(e, "gh.user.id": user_id)
          batch_error = true
          break
        end

        cursor_id = hidden_user_id
        users_processed_this_run += 1
      end

      with_write { Notifications::KV.store.set(CURSOR_KEY, cursor_id.to_s) }

      GitHub.dogstats.increment("purge_hidden_user_subscriptions.batch_processed")
      GitHub.dogstats.gauge("purge_hidden_user_subscriptions.cursor_id", cursor_id)
      break if batch_error
    end

    GitHub.dogstats.gauge("purge_hidden_user_subscriptions.users_processed_per_run", users_processed_this_run)
  end

  private

  sig { params(user_id: Integer).void }
  def delete_subscriptions_for_user(user_id)
    list_sub_count = Newsies::ListSubscription.for_user(user_id).count
    thread_sub_count = Newsies::ThreadSubscription.for_user(user_id).count
    thread_type_sub_count = Newsies::ThreadTypeSubscription.for_user(user_id).count

    GitHub.dogstats.count("purge_hidden_user_subscriptions.subscriptions_enqueued_for_deletion", list_sub_count, tags: ["type:list"])
    GitHub.dogstats.count("purge_hidden_user_subscriptions.subscriptions_enqueued_for_deletion", thread_sub_count, tags: ["type:thread"])
    GitHub.dogstats.count("purge_hidden_user_subscriptions.subscriptions_enqueued_for_deletion", thread_type_sub_count, tags: ["type:thread_type"])

    Notifications::Subscriptions.async_delete_user_subscriptions(user_id)

    Repository.where(owner_id: user_id, user_hidden: true).select(:id).find_in_batches(batch_size: 100) do |repos|
      repos.each do |repo|
        list = Newsies::List.new("Repository", repo.id)
        repo_list_sub_count = Newsies::ListSubscription.for_list(list).count
        repo_thread_sub_count = Newsies::ThreadSubscription.for_list(list).count
        repo_thread_type_sub_count = Newsies::ThreadTypeSubscription.for_list(list).count
        GitHub.dogstats.count("purge_hidden_user_subscriptions.subscriptions_enqueued_for_deletion", repo_list_sub_count, tags: ["type:repository_list"])
        GitHub.dogstats.count("purge_hidden_user_subscriptions.subscriptions_enqueued_for_deletion", repo_thread_sub_count, tags: ["type:repository_thread"])
        GitHub.dogstats.count("purge_hidden_user_subscriptions.subscriptions_enqueued_for_deletion", repo_thread_type_sub_count, tags: ["type:repository_thread_type"])

        subject = Notifications::Subject.new(type: "Repository", id: repo.id)
        Notifications::Subscriptions.async_delete_list_subscriptions(subject)
      end
    end

    GitHub.dogstats.increment("purge_hidden_user_subscriptions.user_purged")
  end
end
