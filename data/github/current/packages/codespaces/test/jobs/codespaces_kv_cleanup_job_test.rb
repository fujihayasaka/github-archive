# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesKvCleanupJobTest < GitHub::TestCase

  test "runs on the kubernetes_codespaces queue" do
    assert_enqueued_jobs TestEnv.enterprise? ? 0 : 1, queue: :kubernetes_codespaces do
      CodespacesKvCleanupJob.perform_later(duration: 60, batch_size: 10)
    end
  end

  test "job is performed and expired rows are deleted when added to the db" do
    CodespacesKvCleanupJob::CodespacesKeyValues.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    CodespacesKvCleanupJob::CodespacesKeyValues.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
    CodespacesKvCleanupJob::CodespacesKeyValues.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

    assert_difference(
      -> { CodespacesKvCleanupJob::CodespacesKeyValues.count } => -2, # 2 rows deleted
    ) do
      CodespacesKvCleanupJob.perform_now(batch_size: 10, duration: 5)
    end
  end
end
