# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class FeatureManagementKvCleanupExpiredDataJob < ApplicationJob
  extend T::Sig

  schedule interval: 6.hours
  queue_as :feature_management_kv_cleanup_expired_data
  retry_on_dirty_exit

  sig { params(batch_size: Integer, duration: Integer).void }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: FeatureManagement::Kv::DataStore, batch_size:)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # schedule to run again if we didn't finish cleanup this time
    self.class.perform_later(batch_size:, duration:) unless result.completed?
  end
end
