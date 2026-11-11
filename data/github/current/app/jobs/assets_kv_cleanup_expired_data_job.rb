# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class AssetsKvCleanupExpiredDataJob < ApplicationJob
  schedule interval: 6.hours
  queue_as :assets_kv_cleanup_expired_data
  retry_on_dirty_exit

  sig { params(batch_size: Integer, duration: Integer).void }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: Assets::KV::DataStore, batch_size:)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # if we didn't finish, schedule another job to continue the cleanup
    AssetsKvCleanupExpiredDataJob.perform_later(batch_size:, duration:) unless result.completed?
  end
end
