# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveStaleAuthenticationRecordsJob < ApplicationJob
  queue_as :remove_stale_authentication_records
  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit
  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 1.day
  schedule interval: 5.minutes, condition: -> { GitHub.sign_in_analysis_enabled? }

  REMOVE_AFTER_DURATION = 9.months
  BATCH_SIZE = 25

  REMOVAL_CONDITIONS = <<-SQL
    created_at < :after
  SQL

  def perform
    authentication_records = AuthenticationRecord.where(REMOVAL_CONDITIONS, {
      after: REMOVE_AFTER_DURATION.ago
    }).limit(BATCH_SIZE)

    loop do
      deleted_records = AuthenticationRecord.throttle_with_retry(max_retry_count: 8, low_priority: true) do
        ActiveRecord::Base.connected_to(role: :writing) do
          authentication_records.delete_all
        end
      end
      GitHub.dogstats.count("account_security.authentication_records", deleted_records, tags: ["action:destroy", "explanation:stale"])
      break if deleted_records < BATCH_SIZE

      # Sleep for 10ms in between each query execution. This gives MySQL a bit more breathing room
      # and should prevent sudden multi-second replication spikes.
      #
      # We're often not deleting enough records for freno to recognize the replication lag and throttling to kick in.
      sleep 0.01
    end
  end
end
