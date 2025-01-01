# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class SignupFlowKvCleanupExpiredDataJob < ApplicationJob
  extend T::Sig

  schedule interval: 2.hours
  queue_as :purge_orphaned_followers
  retry_on_dirty_exit

  class SignupFlowKeyValues < ApplicationRecord::Domain::SignupFlow
    self.table_name = "signup_flow_key_values"
  end

  sig { params(batch_size: Integer, duration: Integer).returns(T.nilable(T.any(SignupFlowKvCleanupExpiredDataJob, FalseClass))) }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: SignupFlowKeyValues, batch_size: batch_size)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # If we didn't complete the cleanup, schedule another job to continue
    SignupFlowKvCleanupExpiredDataJob.perform_later(batch_size: 100, duration: 60) unless result.completed?
  end
end
