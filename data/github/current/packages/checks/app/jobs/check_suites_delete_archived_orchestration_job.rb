# typed: true
# frozen_string_literal: true

class CheckSuitesDeleteArchivedOrchestrationJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  PARALLEL_COUNT = {
    phase3: { peak: 100, off_peak: 120, weekend: 150 },
    phase2: { peak: 80, off_peak: 100, weekend: 120 },
    phase1: { peak: 50, off_peak: 60, weekend: 80 },
    default: { peak: 25, off_peak: 30, weekend: 40 },
  }.freeze

  queue_as :orchestrate_check_suite_deletion
  schedule interval: 30.seconds
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
    rescue ActiveRecord::RecordNotFound, StandardError => e
      Failbot.report(e)
      raise e
    end
  end

  private

  # Approximate number of records that gets deleted per batch. Multiple records can have the same updated_at time so this is not exact
  def offset_per_batch
    2000
  end

  # If changing, make sure the max number does not exceed MAX_DELETE_CONCURRENCY in checks_job_utility.rb
  # Every 5 parallel jobs are ~200k CS deletions per hour
  # Every 25 parallel jobs are ~1M CS deletions per hour
  def parallel_count
    tier = if GitHub.enterprise?
      :enterprise
    elsif FeatureFlag.vexi.enabled?(:checks_retention_parallelism_phase3, default: false)
      :phase3
    elsif FeatureFlag.vexi.enabled?(:checks_retention_parallelism_phase2, default: false)
      :phase2
    elsif FeatureFlag.vexi.enabled?(:checks_retention_parallelism_phase1, default: false)
      :phase1
    else
      :default
    end

    values = effective_parallel_counts(tier)

    if weekend_deletion_window?
      values[:weekend]
    elsif peak_traffic_time?
      values[:peak]
    else
      values[:off_peak]
    end
  end

  # Returns the effective parallel count values for the given tier.
  # For enterprise, ghe-config values override defaults when valid (> 0), capped at MAX_DELETE_CONCURRENCY.
  def effective_parallel_counts(tier)
    return PARALLEL_COUNT[tier] unless tier == :enterprise

    weekday_value = validated_enterprise_config(GitHub.checks_suites_deletion_parallel_count_weekday, 2)
    weekend_value = validated_enterprise_config(GitHub.checks_suites_deletion_parallel_count_weekend, 5)

    {
      peak: weekday_value,
      off_peak: weekday_value,
      weekend: weekend_value,
    }
  end

  def validated_enterprise_config(config_value, default)
    value = [config_value.to_i, MAX_DELETE_CONCURRENCY].min
    value.positive? ? value : default
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

    # Check that all jobs from the previous wave are done before starting a new one.
    # Uses MAX_DELETE_CONCURRENCY to ensure keys from higher-parallelism windows are also checked.
    unless previous_deletions_finished?(MAX_DELETE_CONCURRENCY)
      GitHub.dogstats.increment("checks.orchestrate_check_suite_deletion.previous_deletions_not_finished")
      return
    end
    GitHub.dogstats.count("checks.orchestrate_check_suite_deletion.enqueued_deletions", number_of_batches)

    updated_at_start, updated_at_end = get_updated_at_range_for_first_batch
    return if updated_at_start.nil?

    backlog_age_hours = (Time.now.utc.to_i - updated_at_start.to_i) / 3600
    GitHub.dogstats.gauge("checks.orchestrate_check_suite_deletion.backlog_age_hours", backlog_age_hours)

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
    read_connection do
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
  end

  def get_updated_at_range_for_next_batch(previous_batch_updated_at_end)
    read_connection do
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
end
