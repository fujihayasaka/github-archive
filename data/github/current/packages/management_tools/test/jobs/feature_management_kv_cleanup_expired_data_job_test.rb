# typed: true
# frozen_string_literal: true

require "test_helper"

class FeatureManagementKvCleanupExpiredDataJobTest < GitHub::TestCase
  test "runs on the feature_management_kv_cleanup_expired_data queue" do
    assert_enqueued_jobs 1, queue: :feature_management_kv_cleanup_expired_data do
      FeatureManagementKvCleanupExpiredDataJob.perform_later(duration: 60, batch_size: 100)
    end
  end

  test "job is performed and expired rows are deleted when added to the db" do
    FeatureManagement::Kv::DataStore.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    FeatureManagement::Kv::DataStore.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
    FeatureManagement::Kv::DataStore.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)

    assert_difference(
      -> { FeatureManagement::Kv::DataStore.count } => -2, # 2 rows deleted
    ) do
      FeatureManagementKvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)
    end

    assert_equal 1, FeatureManagement::Kv::DataStore.where(key: "c").count
  end
end
