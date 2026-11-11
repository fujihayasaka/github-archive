# typed: true
# frozen_string_literal: true

# This job will refresh the global notice for active users who have not had their global notice refreshed in the last week
# This job doesn't run in enterprise since we still render the old global notice component there
# This job doesn't run in proxima since the current scheduled notices don't need it
class ScheduledGlobalNoticeRefreshJob < ApplicationJob
  USER_SESSION_INTERVAL = 2.hours
  GLOBAL_NOTICE_INTERVAL = 1.week
  MAX_THROTTLE_RETRIES = 5
  BATCH_SIZE = 1000

  queue_as :scheduled_global_notice_refresh
  schedule interval: 2.hours, condition: -> { !(GitHub.enterprise? || GitHub.multi_tenant_enterprise?) }
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
  retry_on_dirty_exit

  def perform
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
    perform_start = Time.now
    @total_updated = 0

    UserSession.where("accessed_at > ?", USER_SESSION_INTERVAL.ago).select(:user_id).in_batches(of: BATCH_SIZE) do |sessions|
      break if FeatureFlag.vexi.enabled_or_raise?(:disable_scheduled_global_notice_refresh) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      break if @total_updated >= job_limit
      initial_updated = @total_updated

      active_user_ids = sessions.pluck(:user_id)
      all_notices = GlobalNotice.where(user_id: active_user_ids)
      user_ids_to_check = filter_out_notices(active_user_ids, all_notices.where("last_checked_at > ?", GLOBAL_NOTICE_INTERVAL.ago))
      GitHub.dogstats.distribution("scheduled_global_notice_refresh_job.batch.eligible_active_users", user_ids_to_check.length)
      next if user_ids_to_check.empty?

      GlobalNotice.scheduled_notices_by_priority.each do |notice_name, notice_class|
        user_ids = notice_class.find_eligible(user_ids_to_check)
        user_notices = all_notices.where(user_id: user_ids)
        run_scheduled_notice_updates(notice_name, user_notices, user_ids)
        GitHub.dogstats.distribution("scheduled_global_notice_refresh_job.batch.processed_count", @total_updated - initial_updated, tags: ["notice_name:#{notice_name}"])
      end
      run_last_checked_at_updates(user_ids_to_check)
      GitHub.dogstats.increment("scheduled_global_notice_refresh_job.batch.processed")
    end
    GitHub.dogstats.distribution("scheduled_global_notice_refresh_job.processed_count", @total_updated)
    perform_elapsed = GitHub::Dogstats.duration(perform_start, Time.now)
    GitHub.dogstats.distribution("scheduled_global_notice_refresh_job.perform.duration", perform_elapsed)
  end

  private

  def run_scheduled_notice_updates(notice_name, user_notices, user_ids)
    notice_priority = GlobalNotice.names[notice_name]
    user_ids_without_rows = filter_out_notices(user_ids, user_notices)

    with_write_and_throttle do
      update_notices(user_notices, notice_priority)
      insert_notices(user_ids_without_rows, notice_priority)
    end
  end

  def run_last_checked_at_updates(user_ids)
    user_notices = GlobalNotice.where(user_id: user_ids)
    user_ids_without_rows = filter_out_notices(user_ids, user_notices)

    with_write_and_throttle do
      update_last_checked_at(user_notices)
      insert_notices(user_ids_without_rows, GlobalNotice.names[:no_notice])
    end
  end

  def update_notices(user_notices, notice_priority)
    rows = user_notices.where("name = 0 OR name > ?", notice_priority)
    return unless rows.any?
    row_count = rows.length
    rows.update_all(name: notice_priority, last_checked_at: Time.now.utc)
    @total_updated += row_count
  end

  def insert_notices(user_ids_without_rows, notice_priority)
    GitHub.dogstats.distribution("scheduled_global_notice_refresh_job.no_global_notice_row", user_ids_without_rows.length,
      tags: ["notice_name:#{GlobalNotice.names.key(notice_priority)}"])
    return unless user_ids_without_rows.any?
    rows = user_ids_without_rows.map { |user_id| [user_id, notice_priority, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW] }
    GlobalNotice.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
      INSERT IGNORE INTO global_notices
      (user_id, name, created_at, updated_at, last_checked_at)
      :rows
    SQL
    @total_updated += rows.length
  end

  def update_last_checked_at(user_notices)
    rows = user_notices.where("last_checked_at IS NULL OR last_checked_at < ?", GLOBAL_NOTICE_INTERVAL.ago)
    return unless rows.any?
    row_count = rows.length
    rows.update_all(last_checked_at: Time.now.utc)
    GitHub.dogstats.distribution("scheduled_global_notice_refresh_job.update_checked_at", row_count)
    @total_updated += row_count
  end

  def filter_out_notices(user_ids, user_notices_to_filter)
    Set.new(user_ids) - Set.new(user_notices_to_filter.pluck(:user_id))
  end

  # Modify the job limit here to control how many users are processed in a single job run through FFs
  def job_limit
    return 50000 if FeatureFlag.vexi.enabled_or_raise?(:scheduled_global_notice_refresh_job_max_job_limit) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return 10000 if FeatureFlag.vexi.enabled_or_raise?(:scheduled_global_notice_refresh_job_medium_job_limit) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    1000
  end

  def with_write_and_throttle
    with_write do
      GlobalNotice.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        yield
      end
    end
  end
end
