# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

class IprKvCleanupExpiredDataJob < ApplicationJob
  schedule interval: 6.hours
  queue_as :ipr_kv_cleanup_expired_data
  retry_on_dirty_exit

  class IprKeyValues < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "ipr_key_values"
  end

  sig { params(batch_size: Integer, duration: Integer).void }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: IprKeyValues)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # If we didn't finish, schedule another job to continue the cleanup
    IprKvCleanupExpiredDataJob.perform_later(batch_size:, duration:) unless result.completed?
  end
end
