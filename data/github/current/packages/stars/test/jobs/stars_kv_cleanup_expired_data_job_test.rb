# typed: true
# frozen_string_literal: true

require "test_helper"

class StarsKvCleanupExpiredDataJobTest < GitHub::TestCase
  test "runs on the stars_kv_cleanup_expired_data queue" do
    assert_enqueued_jobs 1, queue: :stars_kv_cleanup_expired_data do
      StarsKvCleanupExpiredDataJob.perform_later(duration: 60, batch_size: 100)
    end
  end

  test "job is performed and expired rows are deleted when added to the db" do
    Stars::Kv::DataStore.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    Stars::Kv::DataStore.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
    Stars::Kv::DataStore.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

    assert_difference(
      -> { Stars::Kv::DataStore.count } => -2, # 2 rows deleted
    ) do
      StarsKvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)
    end

    assert_equal 1, Stars::Kv::DataStore.where(key: "c").count
  end
end
