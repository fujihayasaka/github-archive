# typed: true
# frozen_string_literal: true

class RemoveStalePublicKeysJob < ApplicationJob
  queue_as :remove_stale_public_keys
  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit
  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 1.day
  schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

  REMOVE_AFTER_DURATION = 1.year
  BATCH_SIZE = 100

  REMOVAL_CONDITIONS = <<-SQL
    (accessed_at IS NULL AND created_at < :after) or
    (accessed_at < :after)
  SQL

  def perform
    loop do
      keys = PublicKey.where(REMOVAL_CONDITIONS, {
        after: REMOVE_AFTER_DURATION.ago
      }).limit(BATCH_SIZE)

      destroyed_count = PublicKey.throttle_with_retry(max_retry_count: 8) do
        keys.reduce(0) do |destroyed, key|
          GitHub.audit.inline do
            ActiveRecord::Base.connected_to(role: :writing) do
              key.destroy_with_explanation(:stale)
            end
          end
          destroyed + 1
        end
      end

      break if destroyed_count < BATCH_SIZE
    end
  end
end
