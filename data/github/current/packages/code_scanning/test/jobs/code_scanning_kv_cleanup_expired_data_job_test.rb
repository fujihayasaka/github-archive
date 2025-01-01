# typed: strict
# frozen_string_literal: true

require "test_helper"

class CodeScanningKvCleanupExpiredDataJobTest < GitHub::TestCase
  test "job is performed and expired rows are deleted when added to the db" do
    CodeScanning::KV::DataStore.create!(key: "a", value: "a", expires_at: 3.days.ago)
    CodeScanning::KV::DataStore.create!(key: "b", value: "b", expires_at: 2.days.ago)
    CodeScanning::KV::DataStore.create!(key: "c", value: "c", expires_at: 2.minutes.from_now)

    CodeScanningKvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)

    assert_equal 1, CodeScanning::KV::DataStore.count
  end
end
