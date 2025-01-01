# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class KvCleanupExpiredDataJobTest < GitHub::TestCase

    test "runs on the security_center_kv_cleanup_expired_data queue" do
      assert_enqueued_jobs 1, queue: :security_center_kv_cleanup_expired_data do
        SecurityCenter::KvCleanupExpiredDataJob.perform_later(duration: 60, batch_size: 100)
      end
    end

    test "job is performed and expired rows are deleted when added to the db" do
      SecurityCenter::KV::DataStore.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
      SecurityCenter::KV::DataStore.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
      SecurityCenter::KV::DataStore.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

      assert_difference(
        -> { SecurityCenter::KV::DataStore.count } => -2, # 2 rows deleted
      ) do
        SecurityCenter::KvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)
      end

      assert_equal 1, SecurityCenter::KV::DataStore.where(key: "c").count
    end
  end
end
