# typed: true
# frozen_string_literal: true

class CleanExpiredInteractionLimitsJob < ApplicationJob
  BATCH_SIZE = 1_000

  # This job is a background maintenance task that works across a stamp.
  exempt_from_tenant_context_requirement

  schedule interval: 1.day

  # Don't run more than one of this job at a time
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
  queue_as :background_destroy
  retry_on_dirty_exit

  def perform
    loop do
      expired_limit_ids = InteractionLimit.expired.limit(BATCH_SIZE).pluck(:id)
      break if expired_limit_ids.empty?

      with_write do
        InteractionLimit.where(id: expired_limit_ids).delete_all
        raise RuntimeError.new("Unable to purge expired InteractionLimit records") if InteractionLimit.where(id: expired_limit_ids).exists?
      end
    end
  end
end
