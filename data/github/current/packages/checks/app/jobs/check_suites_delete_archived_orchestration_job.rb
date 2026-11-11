# typed: true
# frozen_string_literal: true

class CheckSuitesDeleteArchivedOrchestrationJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  queue_as :orchestrate_check_suite_deletion
  schedule interval: 1.minute
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method :perform
  trace_method :orchestrate_deletion

  exempt_from_tenant_context_requirement

  # There is a large amount of check suites that needs to be deleted and a single job every minute has proven to be too slow. The purpose
  # of this job is to parallelize the deletion process and to increase the total amount of records that can be deleted per minute.
  def perform
    return unless GitHub.checks_retention_enabled?

    lock! do
      orchestrate_deletion
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      raise e
    end
  end

  private

  # Approximate number of records that gets deleted per batch. Multiple records can have the same updated_at time so this is not exact
  def offset_per_batch
    2000
  end

  # If changing, make sure the max number matches the max_concurrent_jobs lock value in check_suites_delete_archived_job.rb
  # Every 5 parallel jobs are ~200k CS deletions per hour
  # Every 25 parallel jobs are ~1M CS deletions per hour
  def parallel_count
    if GitHub.enterprise?
      return 5 if weekend_deletion_window?
      2
    else
      return 25 if peak_traffic_time?
      return 40 if weekend_deletion_window?
      30
    end
  end

  def lock!
    restraint = GitHub::Restraint.new
    lock_key = self.class.name
    max_concurrent_jobs = 1
    lock_ttl = 5.minutes
    restraint.lock!(T.must(lock_key), max_concurrent_jobs, lock_ttl) do
      yield
    end
  rescue GitHub::Restraint::UnableToLock
    # Skip job if we try to run while lock is held
    GitHub.dogstats.increment("checks.orchestrate_check_suite_deletion.unable_to_lock")
  end

  def orchestrate_deletion
    number_of_batches = self.parallel_count

    # before we attempt to kick off any new deletion jobs, check to make sure that the other parallel jobs are done by checking kv
    unless previous_deletions_finished?(number_of_batches)
      GitHub.dogstats.increment("checks.orchestrate_check_suite_deletion.previous_deletions_not_finished")
      return
    end
    GitHub.dogstats.count("checks.orchestrate_check_suite_deletion.enqueued_deletions", number_of_batches)

    updated_at_start, updated_at_end = get_updated_at_range_for_first_batch
    return if updated_at_start.nil?

    number_of_batches.times do |batch_number|
      job_key = "check_suites_delete_archived_job_#{batch_number}"

      if batch_number == 0
        set_concurrency_key_for_batch(job_key)
        CheckSuitesDeleteArchivedJob.perform_later(updated_at_start: updated_at_start, updated_at_end: updated_at_end, concurrent_job_key: job_key)
      else
        updated_at_start, updated_at_end = get_updated_at_range_for_next_batch(updated_at_end)
        return if updated_at_start.nil?

        set_concurrency_key_for_batch(job_key)
        CheckSuitesDeleteArchivedJob.perform_later(updated_at_start: updated_at_start, updated_at_end: updated_at_end, concurrent_job_key: job_key)
      end
    end
  end

  def previous_deletions_finished?(number_of_batches)
    !number_of_batches.times.any? do |batch_number|
      key = "check_suites_delete_archived_job_#{batch_number}"
      concurrency_key_for_batch_exists?(key)
    end
  end

  def get_updated_at_range_for_first_batch
    sql_result = CheckSuite
      .from("check_suites FORCE INDEX(index_check_suites_on_is_archived_updated_at)")
      .where("is_archived = true")
      .where("updated_at <= ?", delete_archived_threshold_days.ago)
      .order("updated_at ASC")
      .limit(1)
      .pluck(:updated_at, :id)

    return nil unless sql_result.present?
    updated_at_start = sql_result[0].first

    # just for extra logging so we can see approximatly what IDs are being deleted
    archive_start_id = sql_result[0].last
    GitHub.dogstats.count("checks.orchestrate_check_suite_deletion.start_id", archive_start_id)

    sql_result = CheckSuite
      .from("check_suites FORCE INDEX(index_check_suites_on_is_archived_updated_at)")
      .where("is_archived = true")
      .where("updated_at <= ?", delete_archived_threshold_days.ago)
      .order("updated_at ASC")
      .limit(1)
      .offset(offset_per_batch)
      .pluck(:updated_at)

    if sql_result.present?
      [updated_at_start, sql_result.first]
    else
      [updated_at_start, updated_at_start]
    end
  end

  def get_updated_at_range_for_next_batch(previous_batch_updated_at_end)
    sql_result = CheckSuite
      .from("check_suites FORCE INDEX(index_check_suites_on_is_archived_updated_at)")
      .where("is_archived = true")
      .where("updated_at > ? AND updated_at <= ?", previous_batch_updated_at_end, delete_archived_threshold_days.ago)
      .order("updated_at ASC")
      .limit(1)
      .pluck(:updated_at)

    return nil unless sql_result.present?
    updated_at_start = sql_result.first

    sql_result = CheckSuite
      .from("check_suites FORCE INDEX(index_check_suites_on_is_archived_updated_at)")
      .where("is_archived = true")
      .where("updated_at > ? AND updated_at <= ?", previous_batch_updated_at_end, delete_archived_threshold_days.ago)
      .order("updated_at ASC")
      .limit(1)
      .offset(offset_per_batch)
      .pluck(:updated_at)

    if sql_result.present?
      [updated_at_start, sql_result.first]
    else
      [updated_at_start, updated_at_start]
    end
  end
end
