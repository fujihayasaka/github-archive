# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job will remove all expired OauthAccesses.
class RemoveExpiredOauthJob < ApplicationJob
  queue_as :remove_expired_oauth
  retry_on_dirty_exit

  schedule interval: 1.minute

  BATCH_SIZE = 100
  MAX_EXECUTION_TIME = 5.minutes

  locked_by timeout: MAX_EXECUTION_TIME + 1.minute, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # This job is exempt from the tenant context requirement because
  # expired accesses should always be removed, regardless of the tenant.
  exempt_from_tenant_context_requirement

  def enabled?; true; end

  def perform
    # Skip processing if we want to disable this job in favor of the orchestration job
    return if FeatureFlag.vexi.enabled?(:disable_remove_expired_oauth_job, default: false)

    end_at = Time.current + MAX_EXECUTION_TIME

    batch_options =
      if FeatureFlag.vexi.enabled?(:remove_expired_oauth_job_cursor_batching, default: false)
        { of: BATCH_SIZE, cursor: [:expires_at, :id], use_ranges: true }
      else
        { of: BATCH_SIZE }
      end

    RefreshToken.inactive.where(refreshable_type: "OauthAccess").in_batches(**batch_options) do |relation|
      refreshable_ids = relation.pluck(:refreshable_id)

      if FeatureFlag.vexi.enabled?(:remove_expired_oauth_job_optimize_primary_reads, default: false)
        # Optimized path: expire_by_ids handles its own write connection,
        # no need to pre-load accesses or wrap in connected_to.
        OauthAccessTokens.domain.expire_by_ids(
          refreshable_ids,
          entry_point: :remove_expired_oauth_job
        )

        # Cleanup refresh tokens that are missing their `refreshable` relation
        # and weren't cleaned up in the `OauthAccess#expire` loop.
        ActiveRecord::Base.connected_to(role: :writing) do
          relation.destroy_all
        end
      else
        # Legacy path: pre-load accesses (unused) and wrap everything in write connection
        # We need to use `to_a` here to force the query to be executed before
        # we establish the write connection below.
        accesses = OauthAccessTokens.domain.by_ids(refreshable_ids)

        ActiveRecord::Base.connected_to(role: :writing) do
          OauthAccessTokens.domain.expire_by_ids(
            refreshable_ids,
            entry_point: :remove_expired_oauth_job
          )

          # Cleanup refresh tokens that are missing their `refreshable` relation
          # and weren't cleaned up in the `OauthAccess#expire` loop.
          relation.destroy_all
        end
      end

      # Check timeout after processing this batch
      if FeatureFlag.vexi.enabled?(:remove_expired_oauth_job_timeout, default: false) && Time.current >= end_at
        return requeue
      end
    end
  end

  private

  def requeue
    clear_lock
    self.class.perform_later
  end
end
