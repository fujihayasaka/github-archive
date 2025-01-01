# typed: true
# frozen_string_literal: true

require "github/config/kv_cleaner"

# This job cleans up codespaces_key_values entries whose expiry date has passed
class CodespacesKvCleanupJob < CodespacesJob

  schedule interval: 6.hours, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit

  class CodespacesKeyValues < ApplicationRecord::Domain::Codespaces
    self.table_name = :codespaces_key_values
  end

  sig { params(batch_size: Integer, duration: Integer).void }
  def perform(batch_size: 10, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: CodespacesKeyValues, batch_size:)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # schedule to run again if we didn't finish cleanup this time
    self.class.perform_later(batch_size:, duration:) unless result.completed?
  end
end
