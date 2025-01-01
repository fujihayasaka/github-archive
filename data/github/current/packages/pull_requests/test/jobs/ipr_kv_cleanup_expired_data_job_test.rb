# typed: true
# frozen_string_literal: true

require "test_helper"

class IprKvCleanupExpiredDataJobTest < GitHub::TestCase
  test "expired rows are deleted" do
    repo = Repository.new(id: 1)
    kv = PullRequests::KV.for_repository(repo)
    kv.set("expired-key", "test-value", expires: 10.minutes.ago)
    kv.set("fresh-key", "test-value", expires: 10.minutes.from_now)

    IprKvCleanupExpiredDataJob.perform_now

    assert_nil kv.get("expired-key").value { nil }
    assert_equal "test-value", kv.get("fresh-key").value { nil }
  end

  test "handles the same key for different repos" do
    kv1 = PullRequests::KV.for_repository(Repository.new(id: 1))
    kv2 = PullRequests::KV.for_repository(Repository.new(id: 2))
    kv1.set("test-key", "kv1-value", expires: 10.minutes.ago)
    kv2.set("test-key", "kv2-value", expires: 10.minutes.from_now)

    IprKvCleanupExpiredDataJob.perform_now

    assert_nil kv1.get("test-key").value { nil }
    assert_equal "kv2-value", kv2.get("test-key").value { nil }
  end
end
