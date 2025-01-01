# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexKvCleanupExpiredDataJobTest < GitHub::TestCase
  test "job is performed and expired rows are deleted when added to the db" do
    MemexKvCleanupExpiredDataJob::MemexKeyValues.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    MemexKvCleanupExpiredDataJob::MemexKeyValues.create!(key: "a", value: "b", expires_at: 2.minutes.ago)
    MemexKvCleanupExpiredDataJob::MemexKeyValues.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

    assert_difference(
      -> { MemexKvCleanupExpiredDataJob::MemexKeyValues.count } => -2, # 2 rows deleted
    ) do
      MemexKvCleanupExpiredDataJob.perform_now(batch_size: 100, max_duration: 5)
    end

    assert_equal "c", T.must(MemexKvCleanupExpiredDataJob::MemexKeyValues.last).key
  end

  test "enqueues another MemexKvCleanupExpiredDataJob if additional expired rows are remaining" do
    MemexKvCleanupExpiredDataJob::MemexKeyValues.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    MemexKvCleanupExpiredDataJob::MemexKeyValues.create!(key: "a", value: "b", expires_at: 2.minutes.ago)

    Timecop.freeze(5.minutes.from_now.utc) do
      assert_performed_jobs(2, only: MemexKvCleanupExpiredDataJob) do
        assert_difference(
          -> { MemexKvCleanupExpiredDataJob::MemexKeyValues.count } => -2, # 2 rows deleted
        ) do
          # we use 0 seconds, which guarantees a single batch is run before exiting
          MemexKvCleanupExpiredDataJob.perform_later(batch_size: 2, max_duration: 0)
        end
      end
    end
  end
end
