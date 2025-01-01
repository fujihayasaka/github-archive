# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class MemexKvCleanupExpiredDataJob < ApplicationJob

  schedule interval: 6.hours
  queue_as :memex_kv_cleanup_expired_data
  retry_on_dirty_exit

  class MemexKeyValues < ApplicationRecord::Domain::Memexes
    self.table_name = "memex_key_values"
  end

  # @param batch_size - The maximum number of rows that we will delete from the table in a single SQL statement.
  #   We may still issue multiple statements of this size within a single job run.
  # @param max_duration - Maximum amount of time, in seconds, that a single instance of this job is allowed to run
  sig { params(batch_size: Integer, max_duration: Integer).void }
  def perform(batch_size: 100, max_duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: MemexKeyValues, batch_size:)
    result = cleaner.cleanup_expired_keys(max_duration: max_duration.seconds)

    # If we didn't complete the cleanup, schedule another job to continue
    MemexKvCleanupExpiredDataJob.perform_later(batch_size:, max_duration:) unless result.completed?
  end
end
