# typed: true
# frozen_string_literal: true

class CheckStepsOrchestrateDeletionJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  queue_as :orchestrate_check_steps_deletion
  schedule interval: 1.minute
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method :perform
  trace_method :orchestrate_deletion

  exempt_from_tenant_context_requirement

  # There is a large amount of step records that needs to be deleted and a single job every minute has proven to be too slow. The purpose
  # of this job is to parallelize the deletion process and to increase the amount of records that can be deleted per minute.
  def perform
    # For now, we're not going to run this in Proxima
    # https://github.com/github/actions-results-team/issues/2256
    # We'll be switching to hot/cold for steps
    return if GitHub.multi_tenant_enterprise?

    # regardless if checks retention is enabled or not, we still want to run this on GHES because the maxmimum retention period for logs on all environments is 400 days and it cannot be incrased

    lock! do
      orchestrate_deletion
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e)
      raise e
    end
  end

  private

  # The amount of days that we have to wait before permanently deleting a check step
  # See actions_retention_limit.rb, the maximum allowed retention period is 400 days for all environments
  def delete_threshold_days
    ChecksJobUtility::DEFAULT_MAX_ARCHIVE_THRESHOLD_IN_DAYS
  end

  def records_per_batch
    45000
  end

  # If changing the total batch size, make sure to adjust the max_concurrent_jobs value in CheckStepsDeleteJob as well
  # This number should match the total max_concurrent_jobs value in check_steps_delete_job.rb
  def parallel_count
    if GitHub.enterprise?
      return 3 if weekend_deletion_window?
    else
      return 20 if weekend_deletion_window?
      return 5 if ramp_up_retention_time?
      return 10 unless peak_traffic_time?
    end
    1
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
    GitHub.dogstats.increment("checks.orchestrate_check_steps_deletion.unable_to_lock")
  end

  def orchestrate_deletion
    # We start with the oldest check step ID based off of the creation time. Checks steps in hosted live in a vitess sharded database where
    # blocks of IDs can be allocated per shard beforehand, so we can't run on the assumption that the smallest ID is the oldest.
    # Reading from the primary to make sure there no stale data from replication lag
    oldest_check_step = ActiveRecord::Base.connected_to(role: :writing) do
      CheckStep
        .where("created_at <= ?", delete_threshold_days.ago)
        .order(id: :asc)
        .limit(1)
        .pluck(:id)
    end

    # All check steps have been deleted so don't schedule anything
    return if oldest_check_step.empty?

    start_id = oldest_check_step.first
    GitHub.dogstats.count("checks.orchestrate_check_steps_deletion.start_id", start_id)

    number_of_batches = self.parallel_count

    # before we attempt to kick off any new deletion jobs, lets check to make sure that the other parallel jobs are done by checking kv
    if previous_deletions_finished?(number_of_batches)
      GitHub.dogstats.count("checks.orchestrate_check_steps_deletion.enqueued_deletions", number_of_batches)
    else
      # A key still exists so a job that was scheduled in the last minute is still running, unsafe to run a new batch of deletion jobs
      GitHub.dogstats.increment("checks.orchestrate_check_steps_deletion.previous_deletions_not_finished")
      return
    end

    batch_size = self.records_per_batch
    GitHub.dogstats.count("checks.orchestrate_check_steps_deletion.batch_size", batch_size)

    number_of_batches.times do |batch_number|
      # Inside the deletion jobs, the IDs are double checked to make sure they are old enough to be deleted
      # Don't check if a record exists with the start_id here because it's possible that the record was deleted
      # by the checks_delete_archive_job which deletes associated records but in no particular order
      end_id = start_id + batch_size - 1

      # We have to use perform_later over perform_now. Perform now runs jobs inline which doesn't achieve the goal of parallelizing deletion
      job_key = "check_steps_delete_job_#{batch_number}"
      set_concurrency_key_for_batch(job_key)
      CheckStepsDeleteJob.perform_later(start_id: start_id, end_id: end_id, concurrent_job_key: job_key)
      start_id = end_id + 1
    end
  end

  def previous_deletions_finished?(number_of_batches)
    number_of_batches.times.all? do |batch_number|
      key = "check_steps_delete_job_#{batch_number}"
      !concurrency_key_for_batch_exists?(key)
    end
  end
end
