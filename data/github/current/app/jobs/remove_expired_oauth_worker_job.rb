# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Worker job that processes a specific batch of expired OAuth tokens.
# Spawned by RemoveExpiredOauthOrchestrationJob for parallel processing.
class RemoveExpiredOauthWorkerJob < ApplicationJob
  queue_as :remove_expired_oauth
  retry_on_dirty_exit

  BATCH_SIZE = 100
  MAX_EXECUTION_TIME = 5.minutes

  # Safety lock timeout - this is just a safety net to prevent accidental duplicate workers.
  # Primary coordination is done via KV keys in the orchestration job.
  # Keep this short (1 minute) since orchestration is the source of truth.
  LOCK_TIMEOUT = 1.minute

  # Max concurrent jobs per worker_index. Each worker_index has its own lock key.
  # If changing the maximum concurrent workers in RemoveExpiredOauthOrchestrationJob#concurrent_worker_count,
  # make sure this number can accommodate all parallel workers.
  MAX_CONCURRENT_JOBS_PER_WORKER_INDEX = 1

  LOCK_KEY_PREFIX = "remove-expired-oauth-worker:"

  exempt_from_tenant_context_requirement

  def perform(token_ids:, worker_index: 0, concurrent_job_key:)
    raise ArgumentError, "token_ids must be present" if token_ids.nil?
    raise ArgumentError, "concurrent_job_key must be present" if concurrent_job_key.blank?

    return unless FeatureFlag.vexi.enabled?(:remove_expired_oauth_job_orchestration, default: false)

    # Safety lock to prevent accidental duplicate workers with the same index.
    # This is a secondary protection - KV-based coordination in orchestration is the primary mechanism.
    with_worker_lock(worker_index) do
      process_tokens(token_ids, worker_index)
    end
  ensure
    # Clear concurrency key after job finishes so orchestration knows this worker has finished
    clear_concurrency_key_for_batch(concurrent_job_key)
  end

  private

  def with_worker_lock(worker_index)
    lock_key = "#{LOCK_KEY_PREFIX}#{worker_index}"
    restraint.lock!(lock_key, MAX_CONCURRENT_JOBS_PER_WORKER_INDEX, LOCK_TIMEOUT) { yield }
  rescue GitHub::Restraint::UnableToLock
    # Lock already held - another worker with this index is running.
    # This is just a safety net, so silently skip and emit metric for monitoring.
    GitHub.dogstats.increment("remove_expired_oauth_worker.lock_contention", tags: ["worker:#{worker_index}"])
  end

  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  def process_tokens(token_ids, worker_index)
    # Leave 10 seconds buffer for cleanup/metrics before job timeout
    end_at = Time.current + MAX_EXECUTION_TIME - 10.seconds
    tokens_processed = 0
    timed_out = T.let(false, T::Boolean)

    RefreshToken.inactive.where(id: token_ids).in_batches(of: BATCH_SIZE) do |relation|
      # Check timeout before processing this batch to avoid exceeding time limit
      if Time.current >= end_at
        timed_out = true
        break
      end

      refreshable_ids = relation.pluck(:refreshable_id)

      OauthAccessTokens.domain.expire_by_ids(
        refreshable_ids,
        entry_point: :remove_expired_oauth_worker_job
      )

      # Cleanup refresh tokens that are missing their `refreshable` relation
      # and weren't cleaned up in the `OauthAccess#expire` loop.
      ActiveRecord::Base.connected_to(role: :writing) do
        RefreshToken.throttle_with_retry(max_retry_count: 3) do
          relation.destroy_all
        end
      end

      tokens_processed += refreshable_ids.size
    end

    # Report metrics for what was actually processed
    status = timed_out ? "timeout" : "completed"
    GitHub.dogstats.count("remove_expired_oauth_worker.refresh_tokens_processed", tokens_processed, tags: ["worker:#{worker_index}", "status:#{status}"])
  end

  # Clear a concurrent_job_key after a parallel running job finishes so the orchestration knows a specific job has finished
  def clear_concurrency_key_for_batch(concurrent_job_key)
    return if concurrent_job_key.blank?

    ActiveRecord::Base.connected_to(role: :writing) do
      Apps::KV.store.del(concurrent_job_key)
    end
  end
end
