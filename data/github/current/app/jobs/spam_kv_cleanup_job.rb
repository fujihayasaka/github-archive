# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "github/config/kv_cleaner"

# This job cleans up spam_key_values entries whose expiry date has passed
class SpamKvCleanupJob < ApplicationJob
  schedule interval: 6.hours, condition: -> { !GitHub.enterprise? }
  queue_as :spam_checks_maintenance
  retry_on_dirty_exit

  class SpamKeyValues < ApplicationRecord::Domain::Spam
    self.table_name = :spam_key_values
  end

  sig { params(batch_size: Integer, duration: Integer).void }
  def perform(batch_size: 100, duration: 60)
    cleaner = GitHub::Config::KVCleaner.new(model_class: SpamKeyValues, batch_size:)
    result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

    # schedule to run again if we didn't finish cleanup this time
    self.class.perform_later(batch_size:, duration:) unless result.completed?
  end
end
