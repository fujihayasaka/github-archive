# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProductsEnablementKvCleanupExpiredDataJobTest < GitHub::TestCase

  test "runs on the security_center_kv_cleanup_expired_data queue" do
    assert_enqueued_jobs 1, queue: :security_products_enablement_kv_cleanup_expired_data do
      SecurityProductsEnablementKvCleanupExpiredDataJob.perform_later(duration: 60, batch_size: 100)
    end
  end

  test "job is performed and expired rows are deleted when added to the db" do
    SecurityProductsEnablementKvCleanupExpiredDataJob::SecurityProductsEnablementKeyValues.create!(key: "foo", value: "bar", expires_at: 2.days.ago)
    SecurityProductsEnablementKvCleanupExpiredDataJob::SecurityProductsEnablementKeyValues.create!(key: "a", value: "b", expires_at: 2.seconds.ago)
    SecurityProductsEnablementKvCleanupExpiredDataJob::SecurityProductsEnablementKeyValues.create!(key: "c", value: "d", expires_at: 2.minutes.from_now)
    SecurityProductsEnablementKvCleanupExpiredDataJob::SecurityProductsEnablementKeyValues.create!(key: "e", value: "f") # no expires_at


    assert_difference(
      -> { SecurityProductsEnablementKvCleanupExpiredDataJob::SecurityProductsEnablementKeyValues.count } => -2, # 2 rows deleted
    ) do
      SecurityProductsEnablementKvCleanupExpiredDataJob.perform_now(batch_size: 100, duration: 5)
    end

    assert_equal 1, SecurityProductsEnablementKvCleanupExpiredDataJob::SecurityProductsEnablementKeyValues.where(key: "c").count
  end
end
