# rubocop:todo GitHub/EnforcePackageAppStructure
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
    keys = PublicKey.where(REMOVAL_CONDITIONS, {
      after: REMOVE_AFTER_DURATION.ago
    }).find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |key|
        begin
          GitHub.audit.inline do
            ActiveRecord::Base.connected_to(role: :writing) do
              key.destroy_with_explanation(:stale)
            end
          end
        rescue Exception => e # rubocop:todo Lint/RescueException
          GitHub.logger.error("remove_stale_public_keys_job failure", "key": key.id, "error": e.message)
        end
      end
    end
  end
end
