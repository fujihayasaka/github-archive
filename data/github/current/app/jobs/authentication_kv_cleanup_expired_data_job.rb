# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class AuthenticationKvCleanupExpiredDataJob < ApplicationJob
  extend T::Sig

  schedule interval: 5.minutes
  queue_as :authentication_kv_cleanup_expired_data
  retry_on_dirty_exit
  DEFAULT_BATCH_SIZE = 100
  DEFAULT_JOB_DURATION = 30

  class AuthenticationKeyValues < ApplicationRecord::Domain::Authentication
    self.table_name = "authentication_key_values"
  end

  sig { params(batch_size: Integer, duration: Integer).returns(T.nilable(T.any(AuthenticationKvCleanupExpiredDataJob, FalseClass))) }
  def perform(batch_size: DEFAULT_BATCH_SIZE, duration: DEFAULT_JOB_DURATION)
    # Only run the job if the feature flag is enabled, otherwise exit early
    if GitHub.flipper[:authentication_kv_cleanup].enabled?
      cleaner = GitHub::Config::KVCleaner.new(model_class: AuthenticationKeyValues, batch_size: batch_size)
      result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

      # If we didn't complete the cleanup, schedule another job to continue
      AuthenticationKvCleanupExpiredDataJob.perform_later(batch_size: DEFAULT_BATCH_SIZE, duration: DEFAULT_JOB_DURATION) unless result.completed?
    end
  end
end
