# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class GrowthNoticeKvCleanupExpiredDataJob < ApplicationJob
  extend T::Sig

  schedule interval: 1.day
  queue_as :growth_notice_kv_cleanup_expired_data
  retry_on_dirty_exit

  class GrowthNoticeKeyValues < ApplicationRecord::Domain::UsersCollab
    self.table_name = "growth_notice_key_values"
  end

  sig { params(batch_size: Integer, duration: Integer).returns(T.nilable(T.any(GrowthNoticeKvCleanupExpiredDataJob, FalseClass))) }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: GrowthNoticeKeyValues, batch_size: batch_size)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # If we didn't complete the cleanup, schedule another job to continue
    GrowthNoticeKvCleanupExpiredDataJob.perform_later(batch_size:, duration:) unless result.completed?
  end
end
