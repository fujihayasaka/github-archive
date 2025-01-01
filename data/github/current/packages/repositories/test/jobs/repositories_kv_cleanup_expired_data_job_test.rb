# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoriesKvCleanupExpiredDataJobTest < GitHub::TestCase
  test "runs on the repositories_kv_cleanup_expired_data queue" do
    assert_enqueued_jobs 1, queue: :repositories_kv_cleanup_expired_data do
      RepositoriesKvCleanupExpiredDataJob.perform_later(duration: 60, batch_size: 100)
    end
  end

  test "job is performed and expired rows are deleted when added to the db" do
    Repositories::Kv::DataStore.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    Repositories::Kv::DataStore.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
    Repositories::Kv::DataStore.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

    assert_difference(
      -> { Repositories::Kv::DataStore.count } => -2, # 2 rows deleted
    ) do
      RepositoriesKvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)
    end

    assert_equal 1, Repositories::Kv::DataStore.where(key: "c").count
  end
end
