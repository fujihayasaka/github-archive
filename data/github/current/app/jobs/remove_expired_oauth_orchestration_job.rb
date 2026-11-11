# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Orchestrates parallel removal of expired OAuth tokens by spawning worker jobs.
# Each worker processes a specific batch of token IDs to avoid overlap and maximize throughput.
class RemoveExpiredOauthOrchestrationJob < ApplicationJob
  queue_as :remove_expired_oauth
  retry_on_dirty_exit

  schedule interval: 10.seconds

  RECORDS_PER_WORKER = 1000

  # Prevent multiple orchestrators from running concurrently
  locked_by timeout: 1.minute, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # This job is exempt from the tenant context requirement because
  # expired accesses should always be removed, regardless of the tenant.
  exempt_from_tenant_context_requirement

  def enabled?
    FeatureFlag.vexi.enabled?(:remove_expired_oauth_job_orchestration, default: false)
  end

  def perform
    return unless enabled?

    # Skip if previous batch of workers is still processing
    if workers_still_running?
      GitHub.dogstats.increment("remove_expired_oauth_orchestration.skipped_workers_busy")
      return
    end

    # Get the first concurrent_worker_count * RECORDS_PER_WORKER expired token IDs.
    # We order ASC (oldest expired first) to process tokens in chronological order,
    # ensuring the longest-expired tokens are removed first.
    total_limit = concurrent_worker_count * RECORDS_PER_WORKER

    expired_refresh_token_ids = RefreshToken.inactive
                                            .where(refreshable_type: "OauthAccess")
                                            .order(expires_at: :asc, id: :asc)
                                            .limit(total_limit)
                                            .pluck(:id)

    return if expired_refresh_token_ids.empty?

    # Split IDs into chunks for each worker and set concurrency keys
    workers_spawned = 0
    expired_refresh_token_ids.each_slice(RECORDS_PER_WORKER).with_index do |expired_ids_batch, index|
      job_key = worker_job_key(index)
      set_concurrency_key_for_parallel_job(job_key)

      RemoveExpiredOauthWorkerJob.perform_later(
        token_ids: expired_ids_batch,
        worker_index: index,
        concurrent_job_key: job_key
      )
      workers_spawned += 1
    end

    GitHub.dogstats.count("remove_expired_oauth_orchestration.refresh_tokens_queued", expired_refresh_token_ids.size)
    GitHub.dogstats.increment("remove_expired_oauth_orchestration.workers_spawned", tags: ["count:#{workers_spawned}"])
  end

  private

  # Maximum possible concurrent workers (used for checking locks).
  # This constant defines the upper limit for concurrent_worker_count scaling.
  # This value can be increased if needed - check performance monitoring before scaling beyond 7.
  MAX_CONCURRENT_WORKERS = 7

  # Returns the number of concurrent workers to spawn (1-MAX_CONCURRENT_WORKERS).
  # Controlled by feature flags for gradual scaling.
  def concurrent_worker_count
    return MAX_CONCURRENT_WORKERS if FeatureFlag.vexi.enabled?(:remove_expired_oauth_orchestration_worker_count_7, default: false)
    return 6 if FeatureFlag.vexi.enabled?(:remove_expired_oauth_orchestration_worker_count_6, default: false)
    return 5 if FeatureFlag.vexi.enabled?(:remove_expired_oauth_orchestration_worker_count_5, default: false)
    return 4 if FeatureFlag.vexi.enabled?(:remove_expired_oauth_orchestration_worker_count_4, default: false)
    return 3 if FeatureFlag.vexi.enabled?(:remove_expired_oauth_orchestration_worker_count_3, default: false)
    return 2 if FeatureFlag.vexi.enabled?(:remove_expired_oauth_orchestration_worker_count_2, default: false)
    1
  end

  # Check if any worker from previous batch is still active.
  # Always checks all possible worker indices (0-6) to handle feature flag toggling.
  # This prevents race conditions when scaling down workers while old ones are still running.
  def workers_still_running?
    (0...MAX_CONCURRENT_WORKERS).any? { |worker_index| concurrency_key_for_batch_exists?(worker_job_key(worker_index)) }
  end

  def worker_job_key(worker_index)
    "remove_expired_oauth_worker_job_#{worker_index}"
  end

  # Orchestration jobs set concurrency keys for parallel running jobs to keep track of completions
  # Each parallel running job has a slightly different concurrency key and before a new batch of jobs is scheduled previous ones are checked to make sure they finished
  def set_concurrency_key_for_parallel_job(concurrent_job_key)
    ActiveRecord::Base.connected_to(role: :writing) do
      Apps::KV.store.set(concurrent_job_key, "true", expires: 5.minutes.from_now)
    end
  end

  def concurrency_key_for_batch_exists?(concurrent_job_key)
    Apps::KV.store.exists(concurrent_job_key).value!
  end
end
