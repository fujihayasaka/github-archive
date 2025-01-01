# typed: strict
# frozen_string_literal: true

require "github/config/kv_cleaner"

module TradeCompliance::TradeScreening
  class KvCleanupExpiredDataJob < ApplicationJob

    schedule interval: 6.hours, condition: -> { !GitHub.enterprise? }
    queue_as :trade_compliance_kv_cleanup_expired_data
    retry_on_dirty_exit

    class TradeComplianceKeyValues < ApplicationRecord::Domain::UsersCollab
      self.table_name = :trade_compliance_key_values
    end

    sig { params(batch_size: Integer, duration: Integer).void }
    def perform(batch_size: 100, duration: 60)
      cleaner = GitHub::Config::KVCleaner.new(model_class: TradeComplianceKeyValues, batch_size: batch_size)
      result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)

      # schedule to run again if we didn't finish cleanup this time
      self.class.perform_later(batch_size: batch_size, duration: duration) unless result.completed?
    end
  end
end
