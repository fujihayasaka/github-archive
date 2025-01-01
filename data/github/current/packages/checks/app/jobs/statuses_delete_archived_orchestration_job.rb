# typed: true
# frozen_string_literal: true

class StatusesDeleteArchivedOrchestrationJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  queue_as :orchestrate_status_deletion
  schedule interval: 1.minute
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method :perform
  trace_method :orchestrate_deletion

  exempt_from_tenant_context_requirement

  # There is a large amount of statuses that needs to be deleted and a single job every minute has proven to be too slow. The purpose
  # of this job is to parallelize the deletion process and to increase the total amount of records that can be deleted per minute.
  def perform
    return unless GitHub.checks_retention_enabled?

    lock! do
      orchestrate_deletion
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e)
      raise e
    end
  end

  private

  # Approximate number of records that get deleted per batch. Multiple records can have the same updated_at time so this is not exact.
  def offset_per_batch
    20000
  end

  # Currently set using feature flags. If changing, make sure the number matches the max_concurrent_jobs lock value in statuses_delete_archived_job.rb
  def parallel_count
    if GitHub.enterprise?
      return 4 if weekend_deletion_window?
    else
      return 6 if weekend_deletion_window?
      return 3 if ramp_up_retention_time?
      return 4 unless peak_traffic_time?
    end
    2
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
    GitHub.dogstats.increment("checks.orchestrate_status_deletion.unable_to_lock")
  end

  def orchestrate_deletion
    number_of_batches = self.parallel_count

    # before we attempt to kick off any new deletion jobs, lets check to make sure that the other parallel jobs are done by checking kv
    if previous_deletions_finished?(number_of_batches)
      GitHub.dogstats.count("checks.orchestrate_status_deletion.enqueued_deletions", number_of_batches)
    else
      # A key still exists so a job that was scheduled in the last minute is still running, unsafe to run a new batch of deletion jobs
      GitHub.dogstats.increment("checks.orchestrate_status_deletion.previous_deletions_not_finished")
      return
    end

    updated_at_start, updated_at_end = get_updated_at_range_for_first_batch
    return if updated_at_start.nil?

    number_of_batches.times do |batch_number|
      job_key = "statuses_delete_archived_job_#{batch_number}"

      if batch_number == 0
        set_concurrency_key_for_parallel_job(job_key)
        StatusesDeleteArchivedJob.perform_later(updated_at_start: updated_at_start, updated_at_end: updated_at_end, concurrent_job_key: job_key)
      else
        updated_at_start, updated_at_end = get_updated_at_range_for_next_batch(updated_at_end)
        return if updated_at_start.nil?

        set_concurrency_key_for_parallel_job(job_key)
        StatusesDeleteArchivedJob.perform_later(updated_at_start: updated_at_start, updated_at_end: updated_at_end, concurrent_job_key: job_key)
      end
    end
  end

  def previous_deletions_finished?(number_of_batches)
    number_of_batches.times do |batch_number|
      key = "statuses_delete_archived_job_#{batch_number}"
      if concurrency_key_for_batch_exists?(key)
        return false
      end
    end

    true
  end

  def get_updated_at_range_for_first_batch
    sql_result = Status
      .from("statuses FORCE INDEX(index_statuses_on_is_archived_updated_at)")
      .where("is_archived = true")
      .where("updated_at <= ?", delete_archived_threshold_days.ago)
      .order("updated_at ASC")
      .limit(1)
      .pluck(:updated_at, :id)

    return nil unless sql_result.present?
    updated_at_start = sql_result[0].first

    # just for extra logging so we can see approximatly what IDs are being deleted
    delete_start_id = sql_result[0].last
    GitHub.dogstats.count("checks.orchestrate_status_deletion.start_id", delete_start_id)

    sql_result = Status
      .from("statuses FORCE INDEX(index_statuses_on_is_archived_updated_at)")
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
    sql_result = Status
      .from("statuses FORCE INDEX(index_statuses_on_is_archived_updated_at)")
      .where("is_archived = true")
      .where("updated_at > ? AND updated_at <= ?", previous_batch_updated_at_end, delete_archived_threshold_days.ago)
      .order("updated_at ASC")
      .limit(1)
      .pluck(:updated_at)

    return nil unless sql_result.present?
    updated_at_start = sql_result.first

    sql_result = Status
      .from("statuses FORCE INDEX(index_statuses_on_is_archived_updated_at)")
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
