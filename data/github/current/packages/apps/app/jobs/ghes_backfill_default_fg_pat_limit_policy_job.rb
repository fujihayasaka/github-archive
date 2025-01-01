# typed: strict
# frozen_string_literal: true

# This job will be executed only on GHES and is responsible for setting the default fine-grained personal access token (FG PAT) expiration limit policy.
class GhesBackfillDefaultFgPatLimitPolicyJob < ApplicationJob
  queue_as :apps_ghes_backfill

  INTERVAL = T.let(1.day, ActiveSupport::Duration)

  schedule interval: INTERVAL, condition: -> { GitHub.enterprise? }
  locked_by timeout: INTERVAL, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  BACKFILL_COMPLETED_KEY = "backfill_default_fg_pat_limit_policy_completed"

  sig { void }
  def perform
    return unless GitHub.enterprise?
    return if Apps::KV.store.exists(BACKFILL_COMPLETED_KEY).value { false } # Skip if already completed
    with_write do
      unless GitHub.global_business.fine_grained_personal_access_token_expiration_limit_enabled?
        GitHub.global_business.set_fine_grained_personal_access_token_expiration_limit(actor: User.ghost, expiration: Configurable::PersonalAccessTokenExpirationLimit::DEFAULT_FINE_GRAINED_PAT_EXPIRATION_LIMIT)
      end

      Apps::KV.store.set(BACKFILL_COMPLETED_KEY, Time.now.rfc3339)
    end
  end
end
