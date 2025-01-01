# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class KvCleanupExpiredDataJobTest < GitHub::TestCase

    test "runs on the trade_compliance_kv_cleanup_expired_data queue" do
      assert_enqueued_jobs 1, queue: :trade_compliance_kv_cleanup_expired_data do
        KvCleanupExpiredDataJob.perform_later(duration: 60, batch_size: 100)
      end
    end

    test "job is performed and expired rows are deleted when added to the db" do
      KvCleanupExpiredDataJob::TradeComplianceKeyValues.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
      KvCleanupExpiredDataJob::TradeComplianceKeyValues.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
      KvCleanupExpiredDataJob::TradeComplianceKeyValues.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

      assert_difference(
        -> { KvCleanupExpiredDataJob::TradeComplianceKeyValues.count } => -2, # 2 rows deleted
      ) do
        KvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)
      end
    end
  end
end
