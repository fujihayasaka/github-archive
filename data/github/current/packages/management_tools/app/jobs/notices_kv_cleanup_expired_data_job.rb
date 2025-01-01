# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class NoticesKvCleanupExpiredDataJob < ApplicationJob
  schedule interval: 6.hours
  queue_as :notices_kv_cleanup_expired_data
  retry_on_dirty_exit

  sig { params(batch_size: Integer, duration: Integer).void }
  def perform(batch_size: 100, duration: 60)
    if GitHub.flipper[:notices_kv_cleanup].enabled?
      cleaner = GitHub::Config::KVCleaner.new(model_class: Notices::Kv::DataStore, batch_size:)
      result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

      # schedule to run again if we didn't finish cleanup this time
      self.class.perform_later(batch_size:, duration:) unless result.completed?
    end
  end
end
