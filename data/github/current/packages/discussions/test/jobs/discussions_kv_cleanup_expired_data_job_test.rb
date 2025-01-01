# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionsKvCleanupExpiredDataJobTest < GitHub::TestCase

  test "runs on the discussions_kv_cleanup_expired_data queue" do
    assert_enqueued_jobs 1, queue: :discussions_kv_cleanup_expired_data do
      DiscussionsKvCleanupExpiredDataJob.perform_later(duration: 60, batch_size: 100)
    end
  end

  test "job is performed and expired rows are deleted when added to the db" do

    Discussions::Kv::DataStore.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    Discussions::Kv::DataStore.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
    Discussions::Kv::DataStore.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

    assert_difference(
      -> { Discussions::Kv::DataStore.count } => -2, # 2 rows deleted
    ) do
      DiscussionsKvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)
    end

    assert_equal 1, Discussions::Kv::DataStore.where(key: "c").count
  end
end
