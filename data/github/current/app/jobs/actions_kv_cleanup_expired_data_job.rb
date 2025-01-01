# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class ActionsKvCleanupExpiredDataJob < ApplicationJob
  extend T::Sig

  schedule interval: 6.hours
  queue_as :actions_kv_cleanup_expired_data
  retry_on_dirty_exit

  class ActionsKeyValues < ApplicationRecord::Domain::RepositoriesActionsChecks
    self.table_name = "actions_key_values"
  end

  sig { params(batch_size: Integer, duration: Integer).returns(T.nilable(T.any(ActionsKvCleanupExpiredDataJob, FalseClass))) }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: ActionsKeyValues)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # If we didn't complete the cleanup, schedule another job to continue
    ActionsKvCleanupExpiredDataJob.perform_later(batch_size: 100, duration: 60) unless result.completed?
  end
end
