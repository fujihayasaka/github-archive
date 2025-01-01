# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class GrowthLastActivityKvCleanupExpiredDataJob < ApplicationJob
  schedule interval: 1.day
  queue_as :growth_last_activity_kv_cleanup_expired_data
  retry_on_dirty_exit

  class GrowthLastActivityKeyValues < ApplicationRecord::Domain::UsersCollab
    self.table_name = "growth_last_activity_key_values"
  end

  sig { params(batch_size: Integer, duration: Integer).returns(T.nilable(T.any(GrowthLastActivityKvCleanupExpiredDataJob, FalseClass))) }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: GrowthLastActivityKeyValues, batch_size: batch_size)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # If we didn't complete the cleanup, schedule another job to continue
    GrowthLastActivityKvCleanupExpiredDataJob.perform_later(batch_size:, duration:) unless result.completed?
  end
end
